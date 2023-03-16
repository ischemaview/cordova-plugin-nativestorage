import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import com.github.hf.leveldb.Iterator;
import com.github.hf.leveldb.LevelDB;
import com.github.hf.leveldb.exception.LevelDBException;

import org.json.JSONObject;
import org.json.JSONException;
import org.apache.cordova.CordovaInterface;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

public class StorageMigrator {
    private final SharedPreferences sharedPref;
    private final SharedPreferences.Editor editor;
    private final CordovaInterface cordova;

    private final Map<String, ValueType> CONVERSION_MAP;
    private static final String TAG = "StorageMigrator";

    enum ValueType {
        STRING,
        BOOLEAN,
        NUMBER,
        OBJECT,
    }

    public StorageMigrator(CordovaInterface cordova, SharedPreferences sharedPref, SharedPreferences.Editor editor) {
        CONVERSION_MAP = new HashMap<>();
        CONVERSION_MAP.put("rapid-username", ValueType.STRING);
        CONVERSION_MAP.put("rapid-user-changed", ValueType.BOOLEAN);
        CONVERSION_MAP.put("rapid-automatic-download", ValueType.BOOLEAN);
        CONVERSION_MAP.put("rapid-app-paused-timestamp", ValueType.NUMBER);
        CONVERSION_MAP.put("rapid-last-activity-timestamp", ValueType.NUMBER);
        CONVERSION_MAP.put("rapid-app-storage", ValueType.STRING);
        CONVERSION_MAP.put("rapid-notification-prompt-request", ValueType.BOOLEAN);
        CONVERSION_MAP.put("rapid-notification-prompt-response", ValueType.BOOLEAN);
        CONVERSION_MAP.put("rapid-rma-cognito-device-key", ValueType.STRING);

        this.sharedPref = sharedPref;
        this.editor = editor;
        this.cordova = cordova;
    }

    private String getRootPath(CordovaInterface cordova) {
        Context context = cordova.getActivity().getApplicationContext();
        return context.getFilesDir().getAbsolutePath().replaceAll("/files", "");
    }

    private String getWebViewRootPath(CordovaInterface cordova) {
        return this.getRootPath(cordova) + "/app_webview";
    }

    private String getLocalStorageRootPath(CordovaInterface cordova) {
        return this.getWebViewRootPath(cordova) + "/Default/Local Storage";
    }

    private Map<String, String> getLocalStorageData(CordovaInterface cordova) throws LevelDBException {
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
        Map<String, String> keyValues = new HashMap<>();

        for (iterator.seekToFirst(); iterator.isValid(); iterator.next()) {
            byte[] key      = iterator.key();
            byte[] value    = iterator.value();
            if(isMeta(key) || isVersion(key)) {
                String keyStr   = new String(key, StandardCharsets.UTF_8);
                String valueStr = new String(value, StandardCharsets.UTF_8);

                keyValues.put(keyStr, valueStr);
                continue;
            }

            String keyStr   = new String(Arrays.copyOfRange(key, 25, key.length), StandardCharsets.UTF_8);
            String valueStr = new String(Arrays.copyOfRange(value, 1, value.length), StandardCharsets.UTF_8);

            keyValues.put(keyStr, valueStr);
            Log.d(TAG, "\tReading key:" + keyStr + " value: " + valueStr.substring(0, Math.min(valueStr.length(), 56)));
        }

        iterator.close(); // closing is a must!

        levelDB.close();

        Log.d(TAG, "getLocalStorageData: get localStorage data.. done");
        return keyValues;
    }

    private boolean isMeta(byte[] key) {
        String keyStr = new String(
                Arrays.copyOfRange(key, 0, Math.min(key.length, 4)),
                StandardCharsets.UTF_8);
        return keyStr.equals("META");
    }

    private boolean isVersion(byte[] key) {
        String keyStr   = new String(key, StandardCharsets.UTF_8);
        return keyStr.equals("VERSION");
    }

    private Boolean isUsername(String key) {
        return key.startsWith("rapid-rma-cognito-device-key");
    }

    private void writeToNativeStorage(String key, String value, ValueType type, SharedPreferences.Editor editor) {
        Log.d(TAG, "\tWriting key:" + key + " value: " + value.substring(0, Math.min(value.length(), 56)));
        switch (type) {
            case NUMBER:
            case BOOLEAN:
            case STRING:
            case OBJECT:
                String newValue = value.replaceAll( "\"", "\\\\\"");
                newValue = "\"" + newValue + "\"";
                editor.putString(key, newValue);
                break;
            default:
                Log.e(TAG, "writeToNativeStorage: Unhandled type: " + type.name());
        }
        Log.d(TAG, "\tDone");
    }

    private void commitToNativeStorage(Map<String, String> keyValues, SharedPreferences.Editor editor) {
        Log.d(TAG, "commitToNativeStorage: Starting to write to shared pref");

        for (Map.Entry<String, String> entry : keyValues.entrySet()) {
            String key   = entry.getKey();
            String value = entry.getValue();

            // If the key isn't in the CONVERSION_MAP or if it doesn't partial match the key
            // string skip writing this entry to the native storage
            if(!CONVERSION_MAP.containsKey(key) && !isUsername(key)) {
                Log.v(TAG, "commitToNativeStorage: skipping key: " + key);
                continue;
            }

            ValueType valueType = CONVERSION_MAP.get(key);
            valueType = valueType != null ? valueType : ValueType.STRING;
            writeToNativeStorage(key, value, valueType, editor);
        }

        Log.d(TAG, "commitToNativeStorage: Writing complete");
    }

    private boolean deleteExistingKeysFromLocalStorage() throws LevelDBException {
        Log.d(TAG, "deleteExistingKeys: cleaning existing localStorage data..");

        String levelDbPath = this.getLocalStorageRootPath(cordova) + "/leveldb";
        Log.d(TAG, "deleteExistingKeys: levelDbPath: " + levelDbPath);

        File levelDbDir = new File(levelDbPath);

        if(!levelDbDir.isDirectory() || !levelDbDir.exists()) {
            Log.w(TAG, "deleteExistingKeys: '" + levelDbPath + "' is not a directory or was not found; Exiting");
            return false;
        }

        LevelDB levelDB   = LevelDB.open(levelDbPath);
        Iterator iterator = levelDB.iterator();

        for (iterator.seekToFirst(); iterator.isValid(); iterator.next()) {
            byte[] key      = iterator.key();
            if(isMeta(key) || isVersion(key)) {
                continue;
            }

            Log.d(TAG, "\tdeleting key:" + new String(key, StandardCharsets.UTF_8));
            levelDB.del(key, true);
        }

        iterator.close(); // closing is a must!
        levelDB.close();

        Log.d(TAG, "deleteExistingKeys: cleaning existing localStorage data.. done");
        return true;
    }

    private boolean migrateDataFromLocalStorage() {
        try {
            Log.d(TAG, "migrateData: Starting migration");

            Map<String, String> keyValues = this.getLocalStorageData(cordova);
            commitToNativeStorage(keyValues, editor);

            boolean didCommit = editor.commit();
            if(!didCommit) {
                Log.w(TAG, "migrateData: failed to commit keyValues to stored pref");
                return false;
            }

            boolean didDelete = deleteExistingKeysFromLocalStorage();
            if(!didDelete) {
                Log.w(TAG, "migrateData: failed to clean up existing local storage");
                return false;
            }

            Log.d(TAG, "migrateData: Migration completed;");
            return true;
        } catch (Exception ex) {
            Log.e(TAG, "migrateData: Migration filed due to error: " + ex.getMessage());
        }
        return false;
    }

    public boolean hasMigrated() {
        return sharedPref.contains("rapid-username");
    }

    public boolean migrate() {
        Log.d(TAG, "migrate: Checking is migration has already run");
        if(this.hasMigrated()) {
            Log.d(TAG, "migrate: hasMigrated() return true");
            return true;
        }
        Log.d(TAG, "migrate: hasMigrated() return false, starting migration");

        return migrateDataFromLocalStorage();
    }
}
