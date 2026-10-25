package com.adilhanney.saber

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

/**
 * A quick memo that can be opened over the lock screen without unlocking,
 * similar to Samsung's Screen Off Memo.
 *
 * It runs `quickMemoMain` in `lib/main.dart` instead of the normal app,
 * which only lets you write a new memo, so other notes aren't revealed
 * while the device is locked.
 *
 * It can be opened from its launcher icon (which can be added as a lock
 * screen shortcut or to the S Pen's Air command menu), or from the
 * Quick Settings tile (see [QuickMemoTileService]).
 */
class QuickMemoActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "quickMemoMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show over the lock screen and turn the screen on
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
