# Flutter Redirectly

A Flutter package for creating and handling dynamic links using your own Redirectly backend. Pure Dart implementation - no native code required!

## Installation

```yaml
dependencies:
  flutter_redirectly: ^2.1.1
```

## Quick Setup

### 1. Get Your API Key

Get your free API key from [redirectly.app](https://redirectly.app) - sign up and create your subdomain to get started.

### 2. Configure Deep Links

**Android** - Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="YOUR_SUBDOMAIN.redirectly.app" />
</intent-filter>
```

**iOS** - Add Associated Domains to `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:YOUR_SUBDOMAIN.redirectly.app</string>
    </array>
</dict>
</plist>
```

If this file doesn't exist, create it. Also ensure your app is properly signed and the Associated Domains capability is enabled in your Apple Developer account.

### 3. Initialize

```dart
import 'package:flutter_redirectly/flutter_redirectly.dart';

final redirectly = FlutterRedirectly();

await redirectly.initialize(RedirectlyConfig(
  apiKey: 'your-api-key-here',
  debug: true,
));
```

### 4. Handle Links

```dart
// Listen for incoming links
redirectly.onLinkClick.listen((linkClick) {
  print('Link: ${linkClick.originalUrl}');
  print('Slug: ${linkClick.slug}');
  
});

// Handle app launch from link
final initialLink = await redirectly.getInitialLink();
if (initialLink != null) {
  // Handle same as above
}
```

### 5. Track App Installs

The plugin automatically tracks app installs on first launch. Listen for install attribution events:

```dart
// Listen for app install events
redirectly.onAppInstalled.listen((installEvent) {
  if (installEvent.matched) {
    // User installed app after clicking a Redirectly link
    print('Install attributed to: ${installEvent.username}/${installEvent.slug}');
    print('Original click time: ${installEvent.clickedAt}');
    
    // Show personalized onboarding or deep link to specific content
    _handleAttributedInstall(installEvent);
  } else {
    // Organic install (no prior link click)
    print('Organic app install');
    _handleOrganicInstall();
  }
});

void _handleAttributedInstall(RedirectlyAppInstallResponse install) {
  // Example: Navigate to the content they were trying to reach
  if (install.linkResolution != null) {
    final target = install.linkResolution!.target;
    // Navigate to target URL or handle accordingly
  }
}
```

**What gets tracked:**

- First app launch only (subsequent launches are ignored)
- Device information (OS, version, timezone, language)
- App information (version, build number)
- Attribution matching with prior link clicks (if any)

**Privacy-friendly:**

- No personal information is collected
- Only standard app/device metadata
- Tracking file prevents duplicate logging
- All data stays within your Redirectly account

### 6. Create Links

```dart
// Create a permanent link
final link = await redirectly.createLink(
  slug: 'my-link',
  target: 'https://example.com',
);
print('Created: ${link.url}');

// Create a temporary link (expires in 1 hour)
final tempLink = await redirectly.createTempLink(
  target: 'https://example.com',
  ttlSeconds: 3600,
);
print('Temp link: ${tempLink.url}');
```

## Complete Attribution Flow

Here's how to implement a complete attribution flow:

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final redirectly = FlutterRedirectly();
  
  @override
  void initState() {
    super.initState();
    _initializeRedirectly();
  }
  
  Future<void> _initializeRedirectly() async {
    await redirectly.initialize(RedirectlyConfig(
      apiKey: 'your-api-key',
      debug: true,
    ));
    
    // Handle ongoing link clicks
    redirectly.onLinkClick.listen(_handleLinkClick);
    
    // Handle app install attribution
    redirectly.onAppInstalled.listen(_handleAppInstall);
    
    // Handle initial link if app was opened via link
    final initialLink = await redirectly.getInitialLink();
    if (initialLink != null) {
      _handleLinkClick(initialLink);
    }
  }
  
  void _handleLinkClick(RedirectlyLinkClick linkClick) {
    print('Link clicked: ${linkClick.slug}');
    
    if (linkClick.linkResolution != null) {
      // Navigate based on link target
      _navigateToTarget(linkClick.linkResolution!.target);
    }
  }
  
  void _handleAppInstall(RedirectlyAppInstallResponse install) {
    if (install.matched) {
      // Show attributed install welcome
      _showAttributedWelcome(install);
    } else {
      // Show standard onboarding
      _showStandardOnboarding();
    }
  }
  
  void _showAttributedWelcome(RedirectlyAppInstallResponse install) {
    // Example: Show personalized welcome message
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Welcome!'),
        content: Text('Thanks for installing from our ${install.slug} link!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigate to the content they were originally trying to reach
              if (install.linkResolution != null) {
                _navigateToTarget(install.linkResolution!.target);
              }
            },
            child: Text('Get Started'),
          ),
        ],
      ),
    );
  }
  
  void _navigateToTarget(String target) {
    // Handle navigation based on your app's routing
    print('Navigating to: $target');
  }
}
```

## Error Handling

```dart
try {
  final link = await redirectly.createLink(slug: 'test', target: 'https://example.com');
} on RedirectlyError catch (e) {
  print('Error: ${e.message}');
}
```

## API Reference

### Configuration

```dart
RedirectlyConfig({
  required String apiKey,     // Your API key
  String? baseUrl,           // Optional: custom domain
  bool enableDebugLogging,   // Optional: debug mode
})
```

### Models

```dart
// Permanent link
RedirectlyLink({
  String id, slug, target, url,
  int clickCount,
  DateTime createdAt,
  Map<String, dynamic>? metadata,
})

// Temporary link  
RedirectlyTempLink({
  String id, slug, target, url,
  int ttlSeconds,
  DateTime expiresAt, createdAt,
})

// Link click event
RedirectlyLinkClick({
  String originalUrl, slug, username,
  DateTime receivedAt,
  RedirectlyError? error,
})

// App install attribution
RedirectlyAppInstallResponse({
  bool matched,              // Whether install was attributed to a link
  String? username, slug,    // Attribution details (if matched)
  DateTime? clickedAt,       // When original link was clicked (if matched)
  RedirectlyLinkResolution? linkResolution, // Original link details
  DateTime loggedAt,         // When install was logged
})
```

### Streams

```dart
// Listen for link clicks (app running or launch)
Stream<RedirectlyLinkClick> redirectly.onLinkClick

// Listen for app install events (first launch only)
Stream<RedirectlyAppInstallResponse> redirectly.onAppInstalled
```

## Testing Install Attribution

During development, you can test install attribution by:

1. **Delete and reinstall your app** to simulate first install
2. **Clear app data** on Android or **delete from device** on iOS  
3. **Click a Redirectly link** → install app → open app
4. The `onAppInstalled` event should fire with `matched: true`

The plugin automatically prevents duplicate install logging by creating a tracking file on first launch.

## Example

See the [example app](./example) for a complete implementation.

## Support

- 🐛 Issues: [GitHub Issues](https://github.com/redirectly-app/flutter_redirectly/issues)
- 📚 Docs: [docs.redirectly.app/](https://docs.redirectly.app/)

## License

MIT License - see [LICENSE](LICENSE) file.
