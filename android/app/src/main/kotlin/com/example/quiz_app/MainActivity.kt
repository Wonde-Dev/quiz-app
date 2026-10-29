package com.example.quiz_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent all screenshots, screen recordings, and app preview captures natively across the app
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
