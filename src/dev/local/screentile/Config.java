package dev.local.screentile;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.DisplayMetrics;
import android.view.WindowManager;

/** Preferencias compartidas de la configuracion de grabacion. */
public final class Config {
    public static final String PREFS = "config";
    public static final String KEY_RES = "res";      // "720" | "1080" | "1440" | "2160"
    public static final String KEY_FPS = "fps";      // "30" | "60" | "90" | "120"
    public static final String KEY_CODEC = "codec";  // "h264" | "h265"
    public static final String KEY_BITRATE = "bitrate"; // 0..100 (0 = automatico)
    public static final String KEY_ABITRATE = "abitrate"; // 128 | 256 | 320
    public static final String KEY_ASOURCE = "asource"; // playback | mic | both | none

    private Config() {}

    static SharedPreferences sp(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static String res(Context c)   { return sp(c).getString(KEY_RES,   "1080"); }
    public static String fps(Context c)   { return sp(c).getString(KEY_FPS,   "60"); }
    public static String codec(Context c) { return sp(c).getString(KEY_CODEC, "h264"); }
    public static int    bitrate(Context c){ return sp(c).getInt(KEY_BITRATE,   0); }
    public static int    abitrate(Context c){ return sp(c).getInt(KEY_ABITRATE, 128); }
    public static String asource(Context c) { return sp(c).getString(KEY_ASOURCE, "playback"); }

    /** max-size que scrcpy debe usar, calculado segun las dimensiones reales
     * de la pantalla y el preset (la dimension corta del target). */
    public static String maxSize(Context c) {
        int targetShort;
        String r = res(c);
        if ("720".equals(r))       targetShort = 720;
        else if ("1440".equals(r)) targetShort = 1440;
        else if ("2160".equals(r)) targetShort = 2160;
        else                       targetShort = 1080; // default incluye "1080"

        try {
            WindowManager wm = (WindowManager) c.getSystemService(Context.WINDOW_SERVICE);
            DisplayMetrics dm = new DisplayMetrics();
            if (wm != null && wm.getDefaultDisplay() != null) {
                wm.getDefaultDisplay().getRealMetrics(dm);
                int w = dm.widthPixels;
                int h = dm.heightPixels;
                if (w > 0 && h > 0) {
                    int shortSide = Math.min(w, h);
                    int longSide  = Math.max(w, h);
                    // calcular a partir del target (sin cap superior; si el target supera
                    // la resolucion nativa, el max-size resultante es >= longSide)
                    int maxDim = (int) Math.round((double) longSide * targetShort / (double) shortSide);
                    if (maxDim < 320) maxDim = 320;
                    return String.valueOf(maxDim);
                }
            }
        } catch (Exception ignored) { }
        // fallback basado en un dispositivo 1080x2400
        if (targetShort <= 720)   return "1600";
        if (targetShort <= 1080)  return "2400";
        return "2400";
    }

    public static String resLabel(Context c) {
        String r = res(c);
        if ("2160".equals(r)) return "4K";
        return r + "p";
    }

    public static void save(Context c, String res, String fps, String codec,
                            int bitrate, int abitrate, String asource) {
        sp(c).edit()
            .putString(KEY_RES, res)
            .putString(KEY_FPS, fps)
            .putString(KEY_CODEC, codec)
            .putInt(KEY_BITRATE, bitrate)
            .putInt(KEY_ABITRATE, abitrate)
            .putString(KEY_ASOURCE, asource)
            .apply();
    }
}
