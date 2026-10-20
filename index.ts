import { registerRootComponent } from 'expo';
import App from './App';
import { Platform } from 'react-native';
const preview = __DEV__ && Platform.OS === 'web' && typeof window !== 'undefined' && window.location.search.includes('preview=library');
registerRootComponent(preview ? require('./tests/LibraryPreview').default : App);
