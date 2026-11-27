package app.flagcast.golf;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    // a cart's scorecard link (flagcast.app/g/<id>/s/<code>, from the invite email or the cart card) opens that scorecard
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        openLink(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        openLink(intent);
    }

    private void openLink(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) return;
        Uri u = intent.getData();
        if (u == null || !"https".equals(u.getScheme()) || !"flagcast.app".equals(u.getHost())) return;
        String path = u.getPath();
        if (path == null || !path.matches("^/g/[a-z0-9]{8}/s/[A-Za-z0-9]{6}/?$")) return;
        String link = u.toString();
        if (getBridge() != null && getBridge().getWebView() != null) getBridge().getWebView().post(() -> getBridge().getWebView().loadUrl(link));
    }
}
