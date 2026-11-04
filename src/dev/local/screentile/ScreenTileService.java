package dev.local.screentile;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

import java.lang.reflect.Method;

public class ScreenTileService extends TileService {

    static final String TAG = "ScreenTile";
    static final String PREFS = "state";
    static final String KEY_REC = "recording";
    static final String SCRIPT = "/data/data/com.termux/files/home/bin/screenrec.sh";
    static final String TERMUX_PKG = "com.termux";
    static final String TERMUX_SERVICE = "com.termux.app.RunCommandService";
    static final String ACTION_RUN = "com.termux.RUN_COMMAND";
    static final String LABEL_ON = "Grabando pantalla";
    static final String LABEL_OFF = "Grabar pantalla";

    private static ScreenTileService sInstance;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private long lastClick = 0L;

    @Override
    public void onCreate() {
        super.onCreate();
        sInstance = this;
    }

    @Override
    public void onDestroy() {
        if (sInstance == this) {
            sInstance = null;
        }
        super.onDestroy();
    }

    @Override
    public void onStartListening() {
        sInstance = this;
        updateTile(isRecording(this));
    }

    @Override
    public void onStopListening() {
        handler.removeCallbacksAndMessages(null);
    }

    @Override
    public void onClick() {
        long now = System.currentTimeMillis();
        if (now - lastClick < 1200L) {
            Log.i(TAG, "click ignorado (debounce)");
            return;
        }
        lastClick = now;

        // Actualizacion inmediata: no esperamos al proceso
        boolean target = !isRecording(this);
        applyState(this, target);
        if (target) {
            runInTermux("start", Config.maxSize(this), Config.fps(this),
                    Config.codec(this), String.valueOf(Config.bitrate(this)),
                    String.valueOf(Config.abitrate(this)) + "K", Config.asource(this), Config.priority(this));
        } else {
            runInTermux("stop");
        }
        // colapsar el panel al pulsar (API oficial, requiere PendingIntent)
        try {
            Intent c = new Intent(this, CollapseActivity.class);
            c.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
            PendingIntent pi = PendingIntent.getActivity(
                    this, 0, c,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            startActivityAndCollapse(pi);
            Log.i(TAG, "startActivityAndCollapse PendingIntent ok");
        } catch (Throwable t) {
            Log.i(TAG, "startActivityAndCollapse fallo: " + t);
            collapsePanel();
        }
    }

    /** Escribe el estado y refresca el tile en vivo (si esta escuchando). */
    static void applyState(Context context, boolean recording) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_REC, recording)
                .apply();
        ScreenTileService s = sInstance;
        if (s != null) {
            s.updateTile(recording);
        }
    }

    static boolean isRecording(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_REC, false);
    }

    private void updateTile(boolean recording) {
        Tile tile = getQsTile();
        if (tile == null) {
            return;
        }
        tile.setState(recording ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setLabel(recording ? LABEL_ON : LABEL_OFF);
        tile.setContentDescription(recording ? "Detener grabación" : "Grabar pantalla");
        if (Build.VERSION.SDK_INT >= 30) {
            // Hint de configuracion activa (solo API 30+)
            String sub = Config.resLabel(this) + " • " +
                    Config.fps(this) + "fps • " +
                    Config.codec(this).toUpperCase();
            tile.setSubtitle(sub);
        }
        tile.updateTile();
    }

    private void collapsePanel() {
        try {
            Object sb = getSystemService(Context.STATUS_BAR_SERVICE);
            Method m = sb.getClass().getMethod("collapsePanels");
            m.invoke(sb);
            Log.i(TAG, "panel colapsado");
        } catch (Throwable t) {
            Log.i(TAG, "no se pudo colapsar el panel (normal en algunas ROM): " + t.getMessage());
        }
    }

    private void runInTermux(final String action) {
        runInTermux(action, null, null, null, null, null, null, null);
    }

    private void runInTermux(final String action,
                             final String maxSize, final String fps,
                             final String codec, final String videoBitrate,
                             final String audioBitrate, final String audioSource,
                             final String priority) {
        Intent i = new Intent();
        i.setClassName(TERMUX_PKG, TERMUX_SERVICE);
        i.setAction(ACTION_RUN);
        i.putExtra("com.termux.RUN_COMMAND_PATH",
                "/data/data/com.termux/files/usr/bin/bash");
        // Se pasan max-size, fps, codec y bitrate al script solo al iniciar.
        String[] args;
        if ("start".equals(action)) {
            args = new String[]{SCRIPT, action,
                    maxSize != null ? maxSize : "2400",
                    fps != null ? fps : "60",
                    codec != null ? codec : "h264",
                    videoBitrate != null ? videoBitrate : "0",
                    audioBitrate != null ? audioBitrate : "128K",
                    audioSource != null ? audioSource : "playback",
                    priority != null ? priority : "very_high"};
        } else {
            args = new String[]{SCRIPT, action};
        }
        i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args);
        i.putExtra("com.termux.RUN_COMMAND_WORKDIR",
                "/data/data/com.termux/files/home");
        i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true);
        i.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0");
        i.putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "Grabar pantalla");
        try {
            startService(i);
            Log.i(TAG, "RUN_COMMAND " + action + " startService ok");
        } catch (Exception e) {
            Log.e(TAG, "startService fallo", e);
            try {
                startForegroundService(i);
                Log.i(TAG, "RUN_COMMAND " + action + " startForegroundService ok");
            } catch (Exception e2) {
                Log.e(TAG, "startForegroundService fallo", e2);
                applyState(this, !"start".equals(action));
            }
        }
    }
}
