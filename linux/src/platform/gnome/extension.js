import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

// The DBus interface for the daemon
const TweakDaemonInterface = `
<node>
  <interface name="org.tweakforeveryone.Daemon">
    <method name="Ping"/>
    <signal name="SetWindowGeometry">
      <arg name="windowId" type="u"/>
      <arg name="x" type="i"/>
      <arg name="y" type="i"/>
      <arg name="width" type="i"/>
      <arg name="height" type="i"/>
    </signal>
    <signal name="SetWindowAlpha">
      <arg name="windowId" type="u"/>
      <arg name="alpha" type="d"/>
    </signal>
    <signal name="WeatherUpdated">
      <arg name="weather" type="s"/>
    </signal>
  </interface>
</node>`;

const TweakProxy = Gio.DBusProxy.makeProxyWrapper(TweakDaemonInterface);

export default class TweakExtension {
    constructor() {
        this._dbusProxy = null;
        this._signalIds = [];
        this._clockUpdateId = 0;
        this._latestWeather = '☀️ Loading...';
    }

    enable() {
        console.log("TweakForEveryone extension enabled");
        
        // Connect to DBus
        this._dbusProxy = new TweakProxy(
            Gio.DBus.session,
            'org.tweakforeveryone.Daemon',
            '/org/tweakforeveryone/Daemon'
        );
        
        this._signalIds.push(this._dbusProxy.connectSignal('WeatherUpdated', (proxy, name, [weather]) => {
            this._latestWeather = weather;
            this._updateClockLabel();
        }));

        // Hook into GNOME Shell Clock
        const dateMenu = Main.panel.statusArea.dateMenu;
        if (dateMenu && dateMenu._clockDisplay) {
            this._clockUpdateId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
                this._updateClockLabel();
                return GLib.SOURCE_CONTINUE;
            });
            this._updateClockLabel();
        }
    }
    
    _updateClockLabel() {
        const dateMenu = Main.panel.statusArea.dateMenu;
        if (!dateMenu || !dateMenu._clockDisplay) return;
        
        const now = GLib.DateTime.new_now_local();
        const t = now.format('%H.%M.%S');
        const d = now.format('%d.%m.%Y');
        
        // Combine them horizontally for the panel
        dateMenu._clockDisplay.set_text(`${t}  |  ${d}  |  ${this._latestWeather}`);
    }

    disable() {
        console.log("TweakForEveryone extension disabled");
        
        if (this._clockUpdateId) {
            GLib.Source.remove(this._clockUpdateId);
            this._clockUpdateId = 0;
        }
        
        this._signalIds.forEach(id => this._dbusProxy.disconnectSignal(id));
        this._signalIds = [];
        this._dbusProxy = null;
        
        // Reset clock
        const dateMenu = Main.panel.statusArea.dateMenu;
        if (dateMenu && dateMenu._clock) {
            dateMenu._clock.notify('clock');
        }
    }
}
