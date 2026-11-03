package dev.local.screentile;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.service.quicksettings.TileService;
import android.util.Log;

public class StateReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        String state = intent.getStringExtra("state");
        boolean recording = "recording".equals(state);
        Log.i(ScreenTileService.TAG, "broadcast state=" + state);
        ScreenTileService.applyState(context, recording);
        try {
            // por si el tile no esta bindeado (panel cerrado)
            TileService.requestListeningState(context,
                    new ComponentName(context, ScreenTileService.class));
        } catch (Exception ignored) {
        }
    }
}
