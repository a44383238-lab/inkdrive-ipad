import { requireOptionalNativeModule } from 'expo-modules-core';
export type Entry = { name: string; path: string; directory: boolean; bytes: number; modified: number };
export type Lesson = {
  schemaVersion: number; id: string; date: string; subject: string; title: string; pdf: string;
  recordings: string[]; materials: string[]; endedAt: string | null;
  requestedOutputs: string[];
};
export type Bridge = {
  getRoot(): Promise<{ name: string } | null>;
  pickFolder(): Promise<{ name: string } | null>;
  list(path: string): Promise<Entry[]>;
  readText(path: string): Promise<string>;
  createFolder(parent: string, name: string): Promise<void>;
  createNote(parent: string, name: string, template: string): Promise<string>;
  openEditor(path: string): Promise<void>;
  pickPDF(): Promise<void>;
  lessons(date: string): Promise<Lesson[]>;
  saveLesson(json: string): Promise<void>;
  importRecording(json: string): Promise<void>;
  startRecording(json: string): Promise<void>;
  quickStartRecording(path: string): Promise<void>;
  stopRecording(): Promise<void>;
  recoverRecording(): Promise<void>;
  archivePendingRecording(): Promise<void>;
  recordingStatus(): Promise<{ active: boolean; seconds: number; pending: boolean; error: string | null }>;
};
export const Native = requireOptionalNativeModule<Bridge>('InkDrive');
