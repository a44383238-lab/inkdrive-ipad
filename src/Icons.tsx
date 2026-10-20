import React from 'react';
import { Image } from 'react-native';
const icons = {
  'arrow-left': require('../assets/icons/arrow-left@3x.png'),
  'arrow-right': require('../assets/icons/arrow-right@3x.png'),
  'chevron-right': require('../assets/icons/chevron-right@3x.png'),
  'book-open': require('../assets/icons/book-open@3x.png'),
  'calendar-days': require('../assets/icons/calendar-days@3x.png'),
  'settings-2': require('../assets/icons/settings-2@3x.png'),
  'folder': require('../assets/icons/folder@3x.png'),
  'folder-open': require('../assets/icons/folder-open@3x.png'),
  'folder-plus': require('../assets/icons/folder-plus@3x.png'),
  'file-text': require('../assets/icons/file-text@3x.png'),
  'search': require('../assets/icons/search@3x.png'),
  'plus': require('../assets/icons/plus@3x.png'),
  'pen-tool': require('../assets/icons/pen-tool@3x.png'),
  'pencil': require('../assets/icons/pencil@3x.png'),
  'highlighter': require('../assets/icons/highlighter@3x.png'),
  'eraser': require('../assets/icons/eraser@3x.png'),
  'lasso-select': require('../assets/icons/lasso-select@3x.png'),
  'type': require('../assets/icons/type@3x.png'),
  'undo-2': require('../assets/icons/undo-2@3x.png'),
  'redo-2': require('../assets/icons/redo-2@3x.png'),
  'ellipsis': require('../assets/icons/ellipsis@3x.png'),
  'grip-vertical': require('../assets/icons/grip-vertical@3x.png'),
  'check': require('../assets/icons/check@3x.png'),
  'x': require('../assets/icons/x@3x.png'),
  'mic': require('../assets/icons/mic@3x.png'),
  'square': require('../assets/icons/square@3x.png'),
  'save': require('../assets/icons/save@3x.png'),
  'layers': require('../assets/icons/layers@3x.png'),
  'sliders-horizontal': require('../assets/icons/sliders-horizontal@3x.png'),
  'minus': require('../assets/icons/minus@3x.png'),
};
export type IconName = keyof typeof icons;
export function Icon({ name, size = 22, color = '#53647C' }: { name: IconName; size?: number; color?: string }) {
  return <Image source={icons[name]} style={{ width: size, height: size, tintColor: color }} resizeMode="contain" accessible={false} />;
}
export function FolderArt({ size = 110 }: { size?: number }) {
  return <Image source={require('../assets/icons/folder-art@3x.png')} style={{ width: size, height: size * 0.8 }} resizeMode="contain" accessible={false} />;
}
