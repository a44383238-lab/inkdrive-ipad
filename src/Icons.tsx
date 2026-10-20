import React from 'react';
import { Image } from 'react-native';
const icons = {
  'arrow-left': require('../assets/icons/arrow-left.png'),
  'arrow-right': require('../assets/icons/arrow-right.png'),
  'chevron-right': require('../assets/icons/chevron-right.png'),
  'book-open': require('../assets/icons/book-open.png'),
  'calendar-days': require('../assets/icons/calendar-days.png'),
  'settings-2': require('../assets/icons/settings-2.png'),
  'folder': require('../assets/icons/folder.png'),
  'folder-open': require('../assets/icons/folder-open.png'),
  'folder-plus': require('../assets/icons/folder-plus.png'),
  'file-text': require('../assets/icons/file-text.png'),
  'search': require('../assets/icons/search.png'),
  'plus': require('../assets/icons/plus.png'),
  'pen-tool': require('../assets/icons/pen-tool.png'),
  'pencil': require('../assets/icons/pencil.png'),
  'highlighter': require('../assets/icons/highlighter.png'),
  'eraser': require('../assets/icons/eraser.png'),
  'lasso-select': require('../assets/icons/lasso-select.png'),
  'type': require('../assets/icons/type.png'),
  'undo-2': require('../assets/icons/undo-2.png'),
  'redo-2': require('../assets/icons/redo-2.png'),
  'ellipsis': require('../assets/icons/ellipsis.png'),
  'grip-vertical': require('../assets/icons/grip-vertical.png'),
  'check': require('../assets/icons/check.png'),
  'x': require('../assets/icons/x.png'),
  'mic': require('../assets/icons/mic.png'),
  'square': require('../assets/icons/square.png'),
  'save': require('../assets/icons/save.png'),
  'layers': require('../assets/icons/layers.png'),
  'sliders-horizontal': require('../assets/icons/sliders-horizontal.png'),
  'minus': require('../assets/icons/minus.png'),
};
export type IconName = keyof typeof icons;
export function Icon({ name, size = 22, color = '#53647C' }: { name: IconName; size?: number; color?: string }) {
  return <Image source={icons[name]} style={{ width: size, height: size, tintColor: color }} resizeMode="contain" accessible={false} />;
}
export function FolderArt({ size = 110 }: { size?: number }) {
  return <Image source={require('../assets/icons/folder-art.png')} style={{ width: size, height: size * 0.8 }} resizeMode="contain" accessible={false} />;
}

