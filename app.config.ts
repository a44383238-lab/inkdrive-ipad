import type { ExpoConfig } from 'expo/config';

const config: ExpoConfig = {
  name: 'InkDrive', slug: 'inkdrive', version: '0.1.0', scheme: 'inkdrive', icon: './assets/icon.png',
  orientation: 'default', userInterfaceStyle: 'light',
  ios: {
    bundleIdentifier: 'app.inkdrive.notes',
    supportsTablet: true,
    infoPlist: {
      LSSupportsOpeningDocumentsInPlace: true,
      UIFileSharingEnabled: true,
      NSMicrophoneUsageDescription: '수업 녹음을 필기 PDF와 연결해 저장하기 위해 마이크를 사용해요.',
      UIBackgroundModes: ['audio'],
    },
  },
  platforms: ['ios', 'web'],
  plugins: [['expo-build-properties', { ios: { deploymentTarget: '17.0' } }]],
};
export default config;
