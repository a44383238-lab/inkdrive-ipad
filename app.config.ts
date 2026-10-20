import type { ExpoConfig } from 'expo/config';

const config: ExpoConfig = {
  name: 'InkDrive', slug: 'inkdrive', version: '0.2.0', scheme: 'inkdrive', icon: './assets/icon.png',
  orientation: 'default', userInterfaceStyle: 'light',
  owner: 'son031027',
  extra: { eas: { projectId: 'a795f3f8-f4a3-4a16-bad2-4f6f0f39ba8e' } },
  ios: {
    bundleIdentifier: 'app.inkdrive.notes',
    buildNumber: '2',
    supportsTablet: true,
    infoPlist: {
      LSSupportsOpeningDocumentsInPlace: true,
      UIFileSharingEnabled: true,
      NSMicrophoneUsageDescription: '수업 녹음을 필기 PDF와 연결해 저장하기 위해 마이크를 사용해요.',
      UIBackgroundModes: ['audio'],
    },
  },
  platforms: ['ios', 'web'],
  plugins: [
    ['expo-build-properties', { ios: { deploymentTarget: '17.0' } }],
    ['expo-dev-client', { launchMode: 'most-recent', defaultLaunchURL: process.env.INKDRIVE_DEV_SERVER_URL ?? 'http://172.21.12.168:8081' }],
  ],
};
export default config;
