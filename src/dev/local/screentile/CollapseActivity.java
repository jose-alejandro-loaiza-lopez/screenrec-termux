package dev.local.screentile;

import android.app.Activity;
import android.os.Bundle;

/**
 * Actividad vacia usada por el tile para colapsar el panel de control rapido.
 * Se lanza con startActivityAndCollapse() y se cierra de inmediato.
 */
public class CollapseActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        finish();
        finishAndRemoveTask();
    }
}
