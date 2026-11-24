package app.flagcast.tv;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * Flagcast TV on Google TV, Android TV and Fire TV: the TV page (flagcast.app/golf/tv/) full screen, kept awake.
 * The page does everything: it shows a code to type in the Manager, then the club's board on tournament days
 * and the club's idle screen in between. The TV's token stays in the page's storage, so it's connected once.
 */
public class MainActivity extends Activity {
    static final String HOME = "https://flagcast.app";
    private WebView web;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean failed = false;

    static String kind() { return "Amazon".equalsIgnoreCase(Build.MANUFACTURER) ? "firetv" : "androidtv"; }

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); // a club screen never sleeps
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0A120E"));
        web.setFocusable(false); // nothing to click on a TV page; the remote's keys come here
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);       // the TV's token
        s.setMediaPlaybackRequiresUserGesture(false); // par 3 cameras and replays play by themselves
        s.setUserAgentString(s.getUserAgentString() + " FlagcastTV/" + BuildConfigVersion.NAME + " (" + kind() + ")");
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl(); // only Flagcast's own pages, nothing else opens on a club TV
                return !"https".equals(u.getScheme()) || !"flagcast.app".equals(u.getHost());
            }
            @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
                if (r.isForMainFrame()) { failed = true; retry(); }
            }
            @Override public void onPageFinished(WebView v, String url) { if (!url.startsWith("data:")) failed = false; }
        });
        setContentView(web);
        immersive();
        if (saved != null) web.restoreState(saved); else load();
    }

    private void load() { web.loadUrl(HOME + "/golf/tv/?kind=" + kind()); }

    /** no internet yet (the TV just came on): a plain notice, then try again every 15 seconds */
    private void retry() {
        web.loadDataWithBaseURL(null, "<html><body style=\"margin:0;background:#0a120e;color:#8fa596;font:3vw sans-serif;display:flex;"
            + "align-items:center;justify-content:center;height:100vh\">Connecting to Flagcast…</body></html>", "text/html", "utf-8", null);
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(() -> { if (failed) load(); }, 15000);
    }

    private void immersive() {
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    @Override public void onWindowFocusChanged(boolean has) { super.onWindowFocusChanged(has); if (has) immersive(); }
    @Override protected void onSaveInstanceState(Bundle out) { super.onSaveInstanceState(out); web.saveState(out); }
    @Override protected void onResume() { super.onResume(); web.onResume(); }
    @Override protected void onPause() { web.onPause(); super.onPause(); }
    @Override protected void onDestroy() { handler.removeCallbacksAndMessages(null); web.destroy(); super.onDestroy(); }

    /** OK / select on the remote reloads (handy if a TV looks stuck); Back leaves the app as usual */
    @Override public boolean onKeyDown(int code, KeyEvent e) {
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER) { load(); return true; }
        return super.onKeyDown(code, e);
    }

    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); }
}
