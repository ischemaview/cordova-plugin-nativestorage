import android.content.Context;
import android.util.Log;

import com.github.hf.leveldb.Iterator;
import com.github.hf.leveldb.LevelDB;
import com.github.hf.leveldb.exception.LevelDBException;

import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaWebView;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

public class MigrateStorage {
    // Switch this value to enable debug mode
    private static final boolean DEBUG_MODE = false;

    private static final String TAG = "com.migrate.android";

    private void logDebug(String message) {
        if(DEBUG_MODE) Log.d(TAG, message);
    }

    private String getRootPath(CordovaInterface cordova) {
        Context context = cordova.getActivity().getApplicationContext();
        return context.getFilesDir().getAbsolutePath().replaceAll("/files", "");
    }

    private String getWebViewRootPath(CordovaInterface cordova) {
        return this.getRootPath(codova) + "/app_webview";
    }

    private String getLocalStorageRootPath(CordovaInterface cordova) {
        return this.getWebViewRootPath(cordova) + "/Local Storage";
    }

    Map<byte[], byte[]> getLocalStorageData(CordovaInterface cordova) throws LevelDBException {
        Log.d(TAG, "getLocalStorageData: get localStorage data..");

        String levelDbPath = this.getLocalStorageRootPath(cordova) + "/leveldb";
        Log.d(TAG, "getLocalStorageData: levelDbPath: " + levelDbPath);

        File levelDbDir = new File(levelDbPath);
        if(!levelDbDir.isDirectory() || !levelDbDir.exists()) {
            Log.w(TAG, "getLocalStorageData: '" + levelDbPath + "' is not a directory or was not found; Exiting");
            return new HashMap<>();
        }

        LevelDB levelDB = LevelDB.open(levelDbPath);
        Iterator iterator = levelDB.iterator();
        Map<byte[], byte[]> keyValues = new HashMap<>();

        for (iterator.seekToFirst(); iterator.isValid(); iterator.next()) {
            byte[] key      = iterator.key();
            byte[] value    = iterator.value();
            String keyStr   = new String(key, StandardCharsets.UTF_8);
            String valueStr = new String(value, StandardCharsets.UTF_8);

            keyValues.put(key, value);
            Log.d(TAG, "Reading key:" + keyStr + " value: " + valueStr.substring(0, Math.min(valueStr.length(), 56)));
        }

        iterator.close(); // closing is a must!

        levelDB.close();

        Log.d(TAG, "getLocalStorageData: get localStorage data.. done");
        return keyValues;
    }


    public void migrateDataFromLocalStorage(CordovaInterface cordova) {
        try {
            logDebug("Starting migration;");
            this.getLocalStorageData(cordova);

            logDebug("Migration completed;");
        } catch (Exception ex) {
            logDebug("Migration filed due to error: " + ex.getMessage());
        }
    }
}
