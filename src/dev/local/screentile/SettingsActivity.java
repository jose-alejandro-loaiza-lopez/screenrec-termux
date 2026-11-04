package dev.local.screentile;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

public class SettingsActivity extends Activity {
    private RadioGroup rgRes, rgFps, rgCodec, rgAudio, rgASource;
    private SeekBar sbBitrate;
    private TextView tvBitrate;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(20);
        root.setPadding(pad, pad, pad, pad);
        scroll.addView(root);

        TextView title = new TextView(this);
        title.setText("Configurar grabación");
        title.setTextSize(20);
        title.setTypeface(null, Typeface.BOLD);
        title.setPadding(0, 0, 0, dp(8));
        root.addView(title);

        TextView hint = new TextView(this);
        hint.setText("Los cambios se guardan automáticamente. Toque normal del tile graba/detiene y cierra el panel.");
        hint.setTextSize(12);
        hint.setTextColor(Color.GRAY);
        hint.setPadding(0, 0, 0, dp(16));
        root.addView(hint);

        rgRes = new RadioGroup(this);
        addSection(root, "Resolución", rgRes);
        addOption(rgRes, "720p", "720");
        addOption(rgRes, "1080p", "1080");
        addOption(rgRes, "1440p", "1440");
        addOption(rgRes, "4K (2160p)", "2160");

        rgFps = new RadioGroup(this);
        addSection(root, "FPS", rgFps);
        addOption(rgFps, "30 fps", "30");
        addOption(rgFps, "60 fps", "60");
        addOption(rgFps, "90 fps", "90");
        addOption(rgFps, "120 fps", "120");

        rgCodec = new RadioGroup(this);
        addSection(root, "Codec de video", rgCodec);
        addOption(rgCodec, "H.264 (máxima compatibilidad)", "h264");
        addOption(rgCodec, "H.265 / HEVC (menor tamaño)", "h265");

        rgASource = new RadioGroup(this);
        addSection(root, "Fuente de audio", rgASource);
        addOption(rgASource, "Audio interno (recomendado)", "playback");
        addOption(rgASource, "Micrófono", "mic");
        addOption(rgASource, "Interno + micrófono", "both");
        addOption(rgASource, "Sin audio", "none");

        rgAudio = new RadioGroup(this);
        addSection(root, "Bitrate de audio (kbps)", rgAudio);
        addOption(rgAudio, "128 kbps", "128");
        addOption(rgAudio, "256 kbps", "256");
        addOption(rgAudio, "320 kbps", "320");

        // bitrate
        TextView brTitle = new TextView(this);
        brTitle.setText("Bitrate (Mbps)");
        brTitle.setTextSize(15);
        brTitle.setTypeface(null, Typeface.BOLD);
        brTitle.setPadding(0, dp(12), 0, dp(4));
        root.addView(brTitle);

        tvBitrate = new TextView(this);
        tvBitrate.setTextSize(14);
        tvBitrate.setPadding(0, 0, 0, dp(4));
        root.addView(tvBitrate);

        sbBitrate = new SeekBar(this);
        sbBitrate.setMax(100);
        root.addView(sbBitrate);

        // seleccion actual
        check(rgRes,   Config.res(this));
        check(rgFps,   Config.fps(this));
        check(rgCodec, Config.codec(this));
        check(rgASource, Config.asource(this));
        check(rgAudio, String.valueOf(Config.abitrate(this)));
        sbBitrate.setProgress(Config.bitrate(this));
        updateBitrateLabel(sbBitrate.getProgress());

        RadioGroup.OnCheckedChangeListener saver = new RadioGroup.OnCheckedChangeListener() {
            @Override public void onCheckedChanged(RadioGroup g, int checkedId) {
                saveNow();
            }
        };
        rgRes.setOnCheckedChangeListener(saver);
        rgFps.setOnCheckedChangeListener(saver);
        rgCodec.setOnCheckedChangeListener(saver);
        rgASource.setOnCheckedChangeListener(saver);
        rgAudio.setOnCheckedChangeListener(saver);

        sbBitrate.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int progress, boolean fromUser) {
                updateBitrateLabel(progress);
                if (fromUser) saveNow();
            }
            @Override public void onStartTrackingTouch(SeekBar s) { }
            @Override public void onStopTrackingTouch(SeekBar s) { saveNow(); }
        });

        setContentView(scroll);
    }

    private void addSection(LinearLayout root, String label, RadioGroup rg) {
        TextView t = new TextView(this);
        t.setText(label);
        t.setTextSize(15);
        t.setTypeface(null, Typeface.BOLD);
        t.setPadding(0, dp(8), 0, dp(4));
        root.addView(t);
        root.addView(rg);
    }

    private void addOption(RadioGroup rg, String label, String value) {
        RadioButton rb = new RadioButton(this);
        rb.setText(label);
        rb.setTag(value);
        rb.setPadding(dp(4), dp(4), dp(4), dp(4));
        rg.addView(rb);
    }

    private void check(RadioGroup rg, String value) {
        for (int i = 0; i < rg.getChildCount(); i++) {
            View v = rg.getChildAt(i);
            if (v instanceof RadioButton && value.equals(v.getTag())) {
                ((RadioButton) v).setChecked(true);
            }
        }
    }

    private String selected(RadioGroup rg) {
        for (int i = 0; i < rg.getChildCount(); i++) {
            View c = rg.getChildAt(i);
            if (c instanceof RadioButton && ((RadioButton) c).isChecked()) {
                return String.valueOf(c.getTag());
            }
        }
        return null;
    }

    private void updateBitrateLabel(int p) {
        if (p <= 0) {
            tvBitrate.setText("0 Mbps (automático por scrcpy)");
        } else {
            tvBitrate.setText(p + " Mbps");
        }
    }

    private void saveNow() {
        String r = selected(rgRes);
        String f = selected(rgFps);
        String c = selected(rgCodec);
        String a = selected(rgAudio);
        String src = selected(rgASource);
        if (r != null && f != null && c != null) {
            int ab = 128;
            try { if (a != null) ab = Integer.parseInt(a); } catch (Exception ignored) {}
            if (src == null) src = "playback";
            Config.save(this, r, f, c, sbBitrate.getProgress(), ab, src);
        }
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }
}
