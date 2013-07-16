using PulseAudio;

public class PulseGlue : GLib.Object{
  private PulseAudio.GLibMainLoop loop;
  private PulseAudio.Context context;
  private Context.Flags cflags;
  private Operation sink_reload_operation;
  private bool has_postponed_sink_reload; 
  private uint postponed_sink_reload_timeout_id;

  bool subscribed;
  bool have_default_card;
  private uint32 default_card_index;
  private uint32 default_sink_index;
  private uint default_sink_num_channels; 

  public PulseGlue(){
    GLib.Object();
  }

  construct{
    this.has_postponed_sink_reload = false;
    this.sink_reload_operation = null;
    this.postponed_sink_reload_timeout_id = -1;
    this.default_card_index = -1;
    this.default_sink_index = -1;
    this.default_sink_num_channels = 0;
    this.subscribed = false;
    this.have_default_card = false;
  }

  public void start(){
    this.loop = new PulseAudio.GLibMainLoop();
    this.context = new PulseAudio.Context(loop.get_api(), null);
    this.cflags = Context.Flags.NOFAIL;
    this.context.set_state_callback(this.context_state_cb);
    this.context.connect( null, this.cflags, null);
  }

  private void run_or_postpone_sink_reload(){
    if(this.sink_reload_operation != null){
      if (this.has_postponed_sink_reload){
        Source.remove(postponed_sink_reload_timeout_id);
      }

      this.postponed_sink_reload_timeout_id = Timeout.add(1000, postponed_sink_reload);
      this.has_postponed_sink_reload = true;
    }else{
      postponed_sink_reload();
      return;
    }
  }

  public void context_state_cb(Context ctx){
    Context.State state = ctx.get_state();
    if (state == Context.State.READY) {
      this.context.get_server_info(this.server_info_cb);
    }
  }
  
  public void server_info_cb(Context ctx, ServerInfo? info){
    if(sink_reload_operation != null) sink_reload_operation.cancel();
    sink_reload_operation = this.context.get_sink_info_by_name(info.default_sink_name, this.sink_info_cb);
    run_or_postpone_sink_reload(); 
  }

  public void sink_info_cb(Context ctx, SinkInfo? info, int eol){
    if(eol > 0) return;
    sink_reload_operation = null;
    bool default_card_changed = !this.have_default_card || this.default_card_index != info.card;
    this.default_card_index = info.card;
    this.default_sink_index = info.index;
    this.default_sink_num_channels = info.volume.channels;

    if(!this.subscribed) {
      this.context.set_subscribe_callback(event_cb);
      this.context.subscribe(Context.SubscriptionMask.SERVER | Context.SubscriptionMask.CARD | Context.SubscriptionMask.SINK);
      this.subscribed = true;
    }

    PulseAudio.Volume volume = info.volume.avg();
    if(volume > PulseAudio.Volume.NORM) volume = PulseAudio.Volume.NORM;
    print("volume: %g\n", volume * 100.0 / PulseAudio.Volume.NORM);

    if(default_card_changed){
      this.context.get_card_info_by_index(this.default_card_index, this.card_info_cb);

    }
  }

  public void event_cb(Context ctx, Context.SubscriptionEventType type, uint32 idx){
    switch (type & Context.SubscriptionEventType.FACILITY_MASK) {
      case Context.SubscriptionEventType.SERVER : this.context.get_server_info(server_info_cb); break;
      case Context.SubscriptionEventType.CARD : {
          if (idx != default_card_index) return;
          this.context.get_card_info_by_index(default_card_index, this.card_info_cb);
        }
        break;
      case Context.SubscriptionEventType.SINK : 
        if (idx == default_sink_index) run_or_postpone_sink_reload();
        break;
      default: break;
    }
  }

  public void card_info_cb(Context c, CardInfo? info, int eol){
    if (eol > 0)
        return;

    if (eol < 0 || info == null) {
        print("Sink info callback failure\n");
        return;
    }
  }

  public bool postponed_sink_reload(){
    if (this.sink_reload_operation != null)
        return true;

    this.context.get_sink_info_by_index(default_sink_index, sink_info_cb);
    has_postponed_sink_reload = false;

    return false;
  }
} 

int main(string args[]){
  Gtk.init(ref args);
  PulseGlue glue = new PulseGlue();
  glue.start();
  Gtk.main();
  return 1;
}
