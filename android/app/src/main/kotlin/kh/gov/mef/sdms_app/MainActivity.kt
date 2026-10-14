package kh.gov.mef.sdms_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // High-importance channel so new-document alerts pop up on screen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "sdms_documents",
                "ឯកសារ",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "ជូនដំណឹងពេលមានឯកសារចូល បញ្ជូនបន្ត ឬបញ្ចប់"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
