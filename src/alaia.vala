using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using WebKit;
using Gee;

namespace alaia {
    class TrackColorSource : GLib.Object {
        private static Gee.ArrayList<string> colors;
        private static int state = 0;
        private static bool initialized = false;
        
        public static void init() {
            if (!TrackColorSource.initialized) {
                stdout.printf("init");
                TrackColorSource.colors = new Gee.ArrayList<string>();
                TrackColorSource.colors.add("#500");
                TrackColorSource.colors.add("#550");
                TrackColorSource.colors.add("#050");
                TrackColorSource.colors.add("#055");
                TrackColorSource.colors.add("#005");
                TrackColorSource.colors.add("#505");
                TrackColorSource.initialized = true;
            }
        }

        public static Clutter.Color get_color() {
            TrackColorSource.init();
            var color = TrackColorSource.colors.get(TrackColorSource.state);
            if (++TrackColorSource.state == TrackColorSource.colors.size) {
                TrackColorSource.state = 0;
            }
            return Clutter.Color.from_string(color);
        }
    }   

    class Track : Clutter.Rectangle {
        private const uint8 OPACITY = 0xE0;
        private Clutter.Actor stage;

        private Track? previous;
        private weak Track? next;
 
        public Track(Clutter.Actor tl, Track? prv, Track? nxt) {
            this.previous = prv;
            this.next = nxt;
            if (this.previous != null) {
                this.previous.next = this;
            }
            if (this.next != null) {
                this.next.previous = this;
            }
            this.add_constraint(
                new Clutter.BindConstraint(tl, Clutter.BindCoordinate.WIDTH, 0)
            );
            this.color = TrackColorSource.get_color();
            this.height = 150;
            this.y = 150;
            this.opacity = Application.S().state == AppState.TRACKLIST ? Track.OPACITY : 0x00;
            this.visible = Application.S().state == AppState.TRACKLIST;
            this.transitions_completed.connect(do_transitions_completed);
            tl.add_child(this);
            this.get_last_track().recalculate_y();
        }

        ~Track(){
            this.next.previous = this.previous;
            this.previous.next = this.next;

            this.get_last_track().recalculate_y();
        }

        private void do_transitions_completed() {
            if (this.opacity == 0x00) {
                this.visible = false;
            }
        }
        public void emerge() {
            this.visible = true;
            this.save_easing_state();
            this.opacity = Track.OPACITY;
            this.restore_easing_state();
        }
        public void disappear() {
            this.save_easing_state();
            this.opacity = 0x00;
            this.restore_easing_state();
        }

        private int calculate_height(){
            //TODO: implement
            return 150;
        }

        private Track get_first_track() {
            return this.previous == null ? this : this.previous.get_first_track();
        }

        private Track get_last_track() {
            return this.next == null ? this : this.next.get_last_track();
        }

        public int recalculate_y(){
            this.save_easing_state();
            int offset = this.previous != null ? this.previous.recalculate_y() : 0;
            this.y = offset;
            this.restore_easing_state();
            return this.calculate_height() + offset;
        }
    }

    class EmptyTrack : Track {
        private Gtk.Entry url_entry;
        private Gtk.Button enter_button;
        private Gtk.HBox hbox;
        private GtkClutter.Actor actor; 
        private TrackList tracklist;

        public EmptyTrack(Clutter.Actor stage, Track? prv, Track? nxt, TrackList tl) {
            base(stage, prv, nxt);
            this.tracklist = tl;
            this.url_entry = new Gtk.Entry();
            this.enter_button = new Gtk.Button.with_label("Go");
            this.hbox = new Gtk.HBox(false, 5);
            this.color = Clutter.Color.from_string("#555");
            this.hbox.pack_start(this.url_entry,true);
            this.hbox.pack_start(this.enter_button,false);
            this.url_entry.activate.connect(do_activate);
            this.actor = new GtkClutter.Actor.with_contents(this.hbox);
            
            this.actor.add_constraint(
                new Clutter.BindConstraint(this, Clutter.BindCoordinate.WIDTH, 0)
            );
            this.actor.add_constraint(
                new Clutter.BindConstraint(this, Clutter.BindCoordinate.Y, 62)  
            );
            
            this.actor.height=25;
            this.actor.transitions_completed.connect(do_transitions_completed);
            this.actor.show_all();
            this.actor.visible = false;

            stage.add_child(this.actor);
            
        }

        private void do_activate() {
            this.tracklist.add_track(this.url_entry.get_text());
        }

        private void do_transitions_completed() {
            if (this.actor.opacity == 0x00) {
                this.actor.visible=false;
            }
        }

        public new void emerge() {
            base.emerge();
            this.actor.visible = true;
            this.actor.save_easing_state();
            this.actor.opacity = 0xE0;
            this.actor.restore_easing_state();
        }

        public new void disappear() {
            base.disappear();
            this.actor.save_easing_state();
            this.actor.opacity = 0x00;
            this.actor.restore_easing_state();
        }
        
    }

    class HistoryTrack : Track {
        private WebKit.WebView web;
        private string url;

        public HistoryTrack(Clutter.Actor stage, Track? prv, Track? nxt, string url, WebView web) {
            base(stage,prv,nxt);
            this.web = web;
            this.web.open(url);
            this.url = url;
        }
    }

    class TrackList : Clutter.Rectangle {
        private Gee.ArrayList<Track> tracks;
        private Clutter.Actor stage;
        private WebKit.WebView web;

        public TrackList(Clutter.Actor stage, WebView web) {
            this.web = web;
            this.tracks = new Gee.ArrayList<Track>();
            this.stage = stage;
            
            this.add_constraint(
                new Clutter.BindConstraint(stage, Clutter.BindCoordinate.SIZE,0)
            );
            this.color = Clutter.Color.from_string("#121212");
            this.reactive=true;
            this.opacity = 0x00;
            this.visible = false;
            this.transitions_completed.connect(do_transitions_completed);
            stage.add_child(this);
            this.add_empty_track();
        }

        public void add_track(string url) {
            Track? next = null;
            Track? previous = null;

            if (this.tracks.size >= 1) {
                next = this.tracks.get(this.tracks.size-1);
            }

            if (this.tracks.size >= 2) {
                previous = this.tracks.get(this.tracks.size-2);
            }

            this.tracks.insert(this.tracks.size-1, 
                new HistoryTrack(this.stage, previous, next, url, this.web)
            );
        }

        private void add_empty_track() {
            this.tracks.insert(this.tracks.size,
                new EmptyTrack(this.stage, null, null,  this)
            );
        }

        /*public bool do_key_press_event(Clutter.KeyEvent e) {
            stdout.printf("buttonpressed\n");
            stdout.printf("%ui\n",e.keyval);
            return true;
        }*/
    
        /*[CCode (instance_pos = -1)]
        public bool do_button_press_event(Clutter.ButtonEvent e) {
            stdout.printf("trcklist\n");
            return true;
        }*/

        private void do_transitions_completed() {
            if (this.opacity == 0x00) {
                this.visible = false;
            }
        }
        
        public void emerge() {
            foreach (Track t in this.tracks) {
                if (t is EmptyTrack) {
                    (t as EmptyTrack).emerge();
                } else {
                    (t as HistoryTrack).emerge();
                }
            }
            this.visible = true;
            this.save_easing_state();
            this.opacity = 0xE0;
            this.restore_easing_state();
        }

        public void disappear() {
            foreach (Track t in this.tracks){
                if (t is EmptyTrack) {
                    (t as EmptyTrack).disappear();
                } else {
                    (t as HistoryTrack).disappear();
                }
            }
            this.save_easing_state();
            this.opacity = 0x00;
            this.restore_easing_state();
        }
    }

    enum AppState {
        NORMAL,
        TRACKLIST
    }

    class Application : Gtk.Application {
        private static Application app;

        private GtkClutter.Window win;
        private WebKit.WebView web;
        private GtkClutter.Actor webact;

        private TrackList tracklist;
        
        private AppState _state;

        public AppState state {
            get {
                return this._state;
            }
        }

        public Application()  {
            GLib.Object(
                application_id : "de.grindhold.alaia",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE,
                register_session : true
            );
            
            this.web = new WebKit.WebView();
            this.webact = new GtkClutter.Actor.with_contents(this.web);

            this.win = new GtkClutter.Window();
            this.win.set_title("alaia");
            this.win.key_press_event.connect(do_key_press_event);
            this.win.destroy.connect(do_delete);

            var stage = this.win.get_stage();
            this.webact.add_constraint(new Clutter.BindConstraint(
                stage, Clutter.BindCoordinate.SIZE, 0)
            );
            stage.add_child(this.webact);
            stage.set_reactive(true);
            //stage.key_press_event.connect(do_key_press_event);
            stage.button_press_event.connect(do_button_press_event);

            this.tracklist = new TrackList(stage, this.web);

            this.win.show_all();
            this.web.open("https://blog.fefe.de");
        }
        
        public void do_delete() {
            Gtk.main_quit();
        }

        public bool do_button_press_event(Clutter.ButtonEvent e) {
            stdout.printf("foobar\n");
            return true;
        }

        public bool do_key_press_event(Gdk.EventKey e) {
            stdout.printf("%u\n",e.keyval);
            stdout.printf("%s\n",e.str);
            switch (this._state) {
                case AppState.NORMAL:
                    switch (e.keyval) {
                        case Gdk.Key.Tab:
                            this.tracklist.emerge();
                            this._state = AppState.TRACKLIST;
                            return true;
                        default:
                            return false;
                    }
                case AppState.TRACKLIST:
                    switch (e.keyval) {
                        case Gdk.Key.Tab:
                            this.tracklist.disappear();
                            this._state = AppState.NORMAL;
                            return true;
                        default:
                            return false;
                    }
            }
            return false;
        }

        public static Application S() {
            return Application.app;
        }
        
        public static int main(string[] args) {
            if (GtkClutter.init(ref args) != Clutter.InitError.SUCCESS){
                stdout.printf("Could not initialize GtkClutter");
            }
            Application.app = new Application();
            Gtk.main();
            return 0;
        }
    }
}