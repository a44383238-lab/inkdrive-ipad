import React from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { LibraryApp } from '../App';
import type { Bridge, Entry } from '../modules/inkdrive';

// Explicit web-only visual fixture. Never reads or writes the user's iCloud files.
const folders: Record<string, string[]> = { '': ['통계학', '산업데이터과학', '작업설계', '강의자료'], '통계학': ['3주차', '교재'] };
const bridge: Bridge = {
  async getRoot() { return { name: 'InkDrive' }; }, async pickFolder() { return { name: 'InkDrive' }; },
  async list(path) { return (folders[path] ?? []).map(name => ({ name, path: [path, name].filter(Boolean).join('/'), directory: true, bytes: 0, modified: 0 } as Entry)); },
  async lessons() { return []; }, async recordingStatus() { return { active: false, seconds: 0, pending: false, error: null }; },
  async readText() { return ''; }, async createFolder() {}, async createNote() { return ''; }, async openEditor() {}, async pickPDF() {},
  async saveLesson() {}, async importRecording() {}, async startRecording() {}, async quickStartRecording() {}, async stopRecording() {}, async recoverRecording() {}, async archivePendingRecording() {},
};
export default function LibraryPreview() { return <SafeAreaProvider><LibraryApp bridge={bridge} /></SafeAreaProvider>; }
