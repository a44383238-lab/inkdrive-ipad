import React, { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useWindowDimensions } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { Native, type Entry, type Lesson } from './modules/inkdrive';
import { cleanName, orderedEntries, SingleFlight, LatestRequest, parentFolder, folderDestination } from './src/domain.mjs';

import { Icon, FolderArt, type IconName } from './src/Icons';

const today = () => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Seoul' }).format(new Date());
const uid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
  const r = Math.floor(Math.random() * 16); return (c === 'x' ? r : (r & 3) | 8).toString(16);
});
type Form = { type: 'folder' | 'note' | 'lesson'; name: string; subject: string; pdf: string; template: string };
type Screen = 'library' | 'today' | 'settings';

function LibraryApp() {
  const compact = useWindowDimensions().width < 700;
  const [screen, setScreen] = useState<Screen>('library');
  const [root, setRoot] = useState<string | null>(null);
  const [path, setPath] = useState('');
  const [rows, setRows] = useState<Entry[]>([]);
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [date, setDate] = useState(today());
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState<Form | null>(null);
  const [resultText, setResultText] = useState<{ title: string; text: string } | null>(null);
  const [recording, setRecording] = useState({ active: false, seconds: 0, pending: false, error: null as string | null });
  const gate = useRef(new SingleFlight()).current;
  const latest = useRef(new LatestRequest()).current;
  async function refresh(folder = path, day = date) {
    if (!Native) return;
    await latest.run(async () => {
      const selected = await Native!.getRoot();
      if (!selected) return { selected: null, entries: [] as Entry[], daily: [] as Lesson[] };
      const [entries, daily] = await Promise.all([Native!.list(folder), Native!.lessons(day)]);
      return { selected, entries, daily };
    }, ({ selected, entries, daily }) => { if (selected) { setRoot(selected.name); setRows(entries); setLessons(daily); } });
  }
  async function run(task: () => Promise<unknown>) {
    try {
      setBusy(true); setError('');
      await gate.run(task);
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
    finally { setBusy(false); }
  }
  useEffect(() => { void refresh(path, date).catch(failure => setError(String(failure))); }, [path, date]);
  useEffect(() => {
    const listener = AppState.addEventListener('change', state => {
      if (state === 'active') { setDate(today()); void refresh().catch(failure => setError(String(failure))); }
    });
    return () => listener.remove();
  }, [path, date]);
  useEffect(() => {
    if (!Native) return;
    let mounted = true;
    const poll = () => { void Native!.recordingStatus().then(value => { if (mounted) setRecording(value); }).catch(() => {}); };
    poll(); const timer = setInterval(poll, 2000);
    return () => { mounted = false; clearInterval(timer); };
  }, []);
  function openForm(type: Form['type'], pdf = '') {
    setForm({ type, name: '', subject: path.split('/').at(-1) ?? '', pdf, template: 'ruled' });
  }
  async function submit() {
    if (!form || !Native) return;
    const value = form;
    await run(async () => {
      const name = cleanName(value.name);
      if (value.type === 'folder') await Native!.createFolder(path, name);
      else if (value.type === 'note') await Native!.createNote(path, name, value.template);
      else {
        if (!value.subject.trim()) throw new Error('과목명을 입력해 주세요.');
        const lesson: Lesson = { schemaVersion: 1, id: uid(), date: today(), subject: value.subject.trim(), title: name,
          pdf: value.pdf, recordings: [], materials: [], endedAt: null, requestedOutputs: ['transcript', 'lecture-notes', 'review-questions'] };
        await Native!.saveLesson(JSON.stringify(lesson));
      }
      setForm(null); await refresh();
      if (value.type === 'lesson') setScreen('today');
    });
  }
  const changeFolder = (next: string) => {
    const destination = folderDestination(path, next);
    if (!destination.changed) { void run(() => refresh(next)); return; }
    setPath(destination.path); setQuery('');
  };
  async function quickRecord(pdf?: string) {
    if (!Native || !root) return;
    await run(async () => {
      if (recording.active) { await Native!.stopRecording(); await refresh(); return; }
      if (typeof Native!.quickStartRecording !== 'function') throw new Error('새 개발용 IPA를 설치해 주세요.');
      let target = pdf;
      if (!target) {
        const stamp = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Seoul', dateStyle: 'short', timeStyle: 'medium' }).format(new Date()).replace(/[: ]/g, '-');
        target = await Native!.createNote(path, '수업 ' + stamp, 'ruled');
      }
      await Native!.quickStartRecording(target);
      setRecording(await Native!.recordingStatus());
      await Native!.openEditor(target); await refresh();
    });
  }
  const iconButton = (icon: IconName, label: string, action: () => void, disabled = false, accent = false) => (
    <Pressable accessibilityRole="button" accessibilityLabel={label} disabled={busy || disabled} onPress={action}
      style={({ pressed }) => [styles.iconButton, accent && styles.accentButton, (busy || disabled) && styles.disabled, pressed && styles.pressed]}>
      <Icon name={icon} color={accent ? '#FFFFFF' : '#53647C'} />
    </Pressable>
  );
  const button = (label: string, action: () => void, secondary = false, disabled = false) => (
    <Pressable accessibilityRole="button" disabled={busy || disabled} onPress={action}
      style={({ pressed }) => [styles.button, secondary && styles.secondary, (busy || disabled) && styles.disabled, pressed && styles.pressed]}>
      <Text style={[styles.buttonText, secondary && styles.secondaryText]}>{label}</Text>
    </Pressable>
  );
  return <SafeAreaView style={[styles.app, compact && { flexDirection: 'column' }]}>
    <StatusBar style="dark" />
    <View style={[styles.sidebar, compact && styles.mobileSidebar]}>
      <View style={styles.brand}><Icon name="pen-tool" color="#FFFFFF" size={24} /></View>
      {(['library', 'today', 'settings'] as Screen[]).map((key, i) => <Pressable key={key} accessibilityRole="tab"
        accessibilityLabel={['서재', '수업', '설정'][i]} accessibilityState={{ selected: screen === key }}
        onPress={() => setScreen(key)} style={({ pressed }) => [styles.nav, screen === key && styles.navSelected, pressed && styles.pressed]}>
        <Icon name={(['book-open', 'calendar-days', 'settings-2'] as IconName[])[i]} size={23} color={screen === key ? '#3565C7' : '#7B8797'} />
      </Pressable>)}
    </View>
    <View style={styles.main}>
      <ScrollView contentContainerStyle={[styles.content, compact && { padding: 20 }]} keyboardShouldPersistTaps="handled">
        {!Native && <Text style={styles.preview}>미리보기</Text>}
        {error ? <View style={styles.error}><Text selectable style={styles.errorText}>{error}</Text>{button('다시 확인', () => void run(() => refresh()), true)}</View> : null}
        {recording.active && <View style={styles.recording}><Text style={styles.errorText}>녹음 · {Math.floor(recording.seconds / 60)}분 {Math.floor(recording.seconds % 60)}초</Text>
          {button('종료', () => void run(async () => { await Native?.stopRecording(); await refresh(); }), true)}</View>}
        {recording.error && <Text style={styles.errorText}>{recording.error}</Text>}
        {recording.pending && !recording.active && <View style={styles.notice}><Text style={styles.noticeText}>미연결 녹음</Text>
          {button('복구', () => void run(async () => { await Native?.recoverRecording(); await refresh(); }), true)}</View>}
        {recording.pending && !recording.active && button('보존하고 새로 시작', () => void run(async () => { await Native?.archivePendingRecording(); await refresh(); }), true)}
        <View style={styles.heading}>
          <Text style={styles.title}>{screen === 'library' ? '서재' : screen === 'today' ? '수업' : '설정'}</Text>
          <View style={styles.actions}>
            {screen === 'library' && <>
              {iconButton('folder-plus', '새 폴더', () => openForm('folder'), !root)}
              {iconButton('file-text', '외부 PDF 열기', () => void run(async () => { await Native?.pickPDF(); await refresh(); }), !Native)}
              {iconButton('plus', '새 노트', () => openForm('note'), !root, true)}
            </>}
            {screen !== 'settings' && <Pressable accessibilityRole="button" accessibilityLabel={recording.active ? '녹음 종료' : '새 수업 녹음'}
              disabled={!root || busy} onPress={() => void quickRecord()} style={[styles.recordButton, (!root || busy) && styles.disabled]}>
              <Icon name={recording.active ? 'square' : 'mic'} color="#C64F60" />
              {recording.active && <Text style={styles.recordTime}>{Math.floor(recording.seconds / 60)}:{String(Math.floor(recording.seconds % 60)).padStart(2, '0')}</Text>}
            </Pressable>}
          </View>
        </View>
        {screen === 'library' && <>
          {!root ? <View style={styles.empty}>
            <FolderArt size={128} />
            {button('폴더 연결', () => void run(async () => { const selected = await Native?.pickFolder(); if (selected) { setPath(''); await refresh(''); } }), false, !Native)}
          </View> : <>
            <View style={styles.locationRow}>
              {iconButton('arrow-left', '상위 폴더', () => changeFolder(parentFolder(path)), !path)}
              <View style={styles.breadcrumb}>
                <Pressable accessibilityRole="button" accessibilityLabel="서재 맨 위로" onPress={() => changeFolder('')} style={styles.crumb}><Text style={styles.rootCrumb}>{root}</Text></Pressable>
                {path.split('/').filter(Boolean).map((part, i, parts) => <View key={i} style={styles.crumbPart}>
                  <Icon name="chevron-right" size={14} color="#A2ADBC" />
                  <Pressable onPress={() => changeFolder(parts.slice(0, i + 1).join('/'))} style={styles.crumb}><Text style={styles.crumbText}>{part}</Text></Pressable>
                </View>)}
              </View>
              <View style={styles.searchWrap}><Icon name="search" size={18} color="#8895A5" /><TextInput accessibilityLabel="파일 검색" style={styles.search} placeholder="검색" value={query} onChangeText={setQuery} /></View>
            </View>
            <View style={styles.grid}>
              {orderedEntries(rows, query).map(row => <View key={row.path} style={styles.fileCard}>
                <Pressable disabled={busy} accessibilityRole="button" accessibilityLabel={row.name} style={({ pressed }) => [styles.fileOpen, pressed && styles.pressed]}
                  onPress={() => row.directory ? changeFolder(row.path) : void run(async () => {
                    if (row.path.toLowerCase().endsWith('.pdf')) await Native!.openEditor(row.path);
                    else setResultText({ title: row.name, text: await Native!.readText(row.path) });
                    await refresh();
                  })}>
                  {row.directory ? <FolderArt /> : <View style={styles.paper}><Icon name="file-text" size={40} color="#7D91AD" /><View style={styles.paperLine} /><View style={[styles.paperLine, { width: 34 }]} /></View>}
                  <Text numberOfLines={2} style={styles.fileTitle}>{row.name.replace(/\.pdf$/i, '')}</Text>
                </Pressable>
                {!row.directory && row.path.toLowerCase().endsWith('.pdf') && <View style={styles.cardActions}>
                  {iconButton('mic', row.name + ' 녹음', () => void quickRecord(row.path))}
                  {iconButton('calendar-days', '수업 연결', () => openForm('lesson', row.path))}
                </View>}
              </View>)}
            </View>
            {!rows.length && <View style={styles.empty}><FolderArt size={92} /><Text style={styles.small}>비어 있어요</Text>{iconButton('plus', '새 노트', () => openForm('note'), false, true)}</View>}
          </>}
        </>}
        {screen === 'today' && <>
          <View style={styles.dayRow}><Text style={styles.small}>{date}</Text>{iconButton('folder-open', '정리 결과', () => { setScreen('library'); changeFolder('AI'); }, !root)}</View>
          {!lessons.length && <View style={styles.empty}><Icon name="calendar-days" size={40} color="#8DA5C8" /><Text style={styles.small}>수업 없음</Text></View>}
          {lessons.map(lesson => <View key={lesson.id} style={styles.lesson}>
            <View style={styles.lessonHeading}><View style={styles.flex}><Text style={styles.small}>{lesson.subject}</Text><Text style={styles.sectionTitle}>{lesson.title}</Text></View><Text style={styles.chip}>{lesson.endedAt ? '종료' : '진행 중'}</Text></View>
            <View style={styles.actions}>
              {iconButton('pen-tool', '필기 열기', () => void run(async () => { await Native!.openEditor(lesson.pdf); await refresh(); }))}
              {iconButton('mic', '녹음', () => void quickRecord(lesson.pdf), recording.active)}
              {iconButton('plus', '녹음 가져오기', () => void run(async () => { await Native!.importRecording(JSON.stringify(lesson)); await refresh(); }), recording.active)}
              {button(lesson.endedAt ? '다시 열기' : '수업 종료', () => void run(async () => {
                if (recording.active) await Native!.stopRecording();
                const latestLessons = await Native!.lessons(date);
                const current = latestLessons.find(value => value.id === lesson.id) ?? lesson;
                await Native!.saveLesson(JSON.stringify({ ...current, endedAt: current.endedAt ? null : new Date().toISOString() })); await refresh();
              }), true)}
              <Text style={styles.small}>녹음 {lesson.recordings.length}</Text>
            </View>
          </View>)}
        </>}
        {screen === 'settings' && <>
          <View style={styles.lesson}><Text style={styles.small}>서재</Text><Text style={styles.sectionTitle}>{root ?? '연결 안 됨'}</Text>
            {button('폴더 선택', () => void run(async () => { if (await Native?.pickFolder()) { setPath(''); await refresh(''); } }), true, !Native || recording.active)}</View>
          <View style={styles.lesson}><Text style={styles.small}>수업 정리</Text><Text style={styles.sectionTitle}>22:00</Text><Text style={styles.small}>전사 · 노트 · 문제</Text></View>
        </>}
      </ScrollView>
      {busy && <View style={styles.busy} pointerEvents="none"><ActivityIndicator color="#2455D6" /><Text style={styles.small}>처리 중…</Text></View>}
    </View>
    <Modal visible={form !== null} transparent animationType="fade" onRequestClose={() => { if (!busy) setForm(null); }}>
      <View style={styles.modalBackdrop}><View style={styles.modal}>
        <Text style={styles.sectionTitle}>{form?.type === 'folder' ? '새 폴더' : form?.type === 'note' ? '새 노트' : '오늘 수업 연결'}</Text>
        <TextInput autoFocus style={styles.input} placeholder={form?.type === 'lesson' ? '수업 제목' : '이름'} value={form?.name} onChangeText={name => setForm(value => value && ({ ...value, name }))} />
        {form?.type === 'lesson' && <><TextInput style={styles.input} placeholder="과목명" value={form.subject} onChangeText={subject => setForm(value => value && ({ ...value, subject }))} /><Text style={styles.small}>{form.pdf}</Text></>}
        {form?.type === 'note' && <View style={styles.actions}>{['plain', 'ruled', 'grid'].map((template, i) => <Pressable key={template} onPress={() => setForm(value => value && ({ ...value, template }))} style={[styles.chip, form.template === template && styles.navSelected]}><Text>{['무지', '줄노트', '모눈'][i]}</Text></Pressable>)}</View>}
        {error ? <Text style={styles.errorText}>{error}</Text> : null}
        <View style={styles.actions}>{button('취소', () => setForm(null), true)}{button('만들기', () => void submit())}</View>
      </View></View>
    </Modal>
    <Modal visible={resultText !== null} animationType="slide" onRequestClose={() => setResultText(null)}>
      <SafeAreaView style={{ flex: 1, padding: 20, backgroundColor: '#FAFBFD' }}>
        <Text style={styles.sectionTitle}>{resultText?.title}</Text>{button('서재', () => setResultText(null), true)}
        <ScrollView style={{ marginTop: 20 }}><Text selectable style={[styles.body, { color: '#263B5A' }]}>{resultText?.text}</Text></ScrollView>
      </SafeAreaView>
    </Modal>
  </SafeAreaView>;
}
export default function App() { return <SafeAreaProvider><LibraryApp /></SafeAreaProvider>; }

const styles = StyleSheet.create({
  app: { flex: 1, flexDirection: 'row', backgroundColor: '#F8F9FC' },
  sidebar: { width: 80, backgroundColor: '#EEF2F7', alignItems: 'center', paddingTop: 24, borderRightWidth: 1, borderRightColor: '#E3E8F0', gap: 16 },
  mobileSidebar: { width: '100%', flexDirection: 'row', paddingTop: 8, paddingHorizontal: 16, paddingBottom: 8, gap: 12, borderRightWidth: 0, borderBottomWidth: 1, borderBottomColor: '#E3E8F0' },
  brand: { width: 44, height: 44, borderRadius: 15, backgroundColor: '#3665BF', alignItems: 'center', justifyContent: 'center', marginBottom: 24 },
  nav: { width: 48, height: 48, borderRadius: 15, alignItems: 'center', justifyContent: 'center' }, navSelected: { backgroundColor: '#DCE6F8' },
  main: { flex: 1 }, content: { padding: 36, width: '100%', maxWidth: 1250, alignSelf: 'center', paddingBottom: 80 },
  heading: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24, flexWrap: 'wrap', gap: 12 },
  title: { fontSize: 30, fontWeight: '700', color: '#24364F', letterSpacing: -0.7 },
  sectionTitle: { fontSize: 18, fontWeight: '600', color: '#2C405B', marginVertical: 8 },
  small: { fontSize: 12, color: '#65758B', lineHeight: 20 }, body: { fontSize: 14, lineHeight: 24, color: '#53647B' },
  preview: { fontSize: 11, color: '#8B96A7', marginBottom: 12 },
  button: { paddingHorizontal: 18, minHeight: 44, justifyContent: 'center', backgroundColor: '#3665BF', borderRadius: 12, alignItems: 'center' },
  secondary: { backgroundColor: '#EDF1F7' }, buttonText: { fontSize: 13, fontWeight: '600', color: 'white' }, secondaryText: { color: '#4C617E' },
  disabled: { opacity: 0.35 }, pressed: { opacity: 0.65 }, actions: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 8 },
  iconButton: { width: 44, height: 44, borderRadius: 13, alignItems: 'center', justifyContent: 'center', backgroundColor: '#EDF1F6' }, accentButton: { backgroundColor: '#3665BF' },
  recordButton: { minWidth: 48, height: 44, borderRadius: 13, alignItems: 'center', justifyContent: 'center', flexDirection: 'row', paddingHorizontal: 13, backgroundColor: '#FBECEE', gap: 8 }, recordTime: { color: '#C64F60', fontVariant: ['tabular-nums'], fontSize: 13 },
  locationRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: 26, flexWrap: 'wrap' },
  breadcrumb: { flex: 1, flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', minWidth: 120 }, crumbPart: { flexDirection: 'row', alignItems: 'center' },
  crumb: { minHeight: 44, justifyContent: 'center', paddingHorizontal: 5 }, rootCrumb: { fontWeight: '600', color: '#435D80', fontSize: 14 }, crumbText: { color: '#66798F', fontSize: 13 },
  searchWrap: { flexDirection: 'row', gap: 9, alignItems: 'center', backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E4E9F1', paddingHorizontal: 13, borderRadius: 13, width: 190, height: 44 }, search: { flex: 1, fontSize: 13, color: '#334A67', height: 44 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 18, alignItems: 'flex-start' },
  fileCard: { width: 152, minHeight: 150, borderRadius: 17, padding: 9, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E8ECF3' },
  fileOpen: { alignItems: 'center', justifyContent: 'center', paddingTop: 5, gap: 12, minHeight: 136 },
  fileTitle: { color: '#344A65', fontWeight: '500', fontSize: 13, textAlign: 'center', lineHeight: 19, minHeight: 23, paddingHorizontal: 3 },
  paper: { width: 68, height: 85, borderRadius: 7, borderWidth: 1, borderColor: '#DCE4EF', backgroundColor: '#F9FBFE', alignItems: 'center', justifyContent: 'center', gap: 7 }, paperLine: { width: 42, height: 2, backgroundColor: '#DEE6F2', borderRadius: 2 },
  cardActions: { flexDirection: 'row', justifyContent: 'center', gap: 10, marginTop: 5 },
  empty: { marginVertical: 35, alignItems: 'center', padding: 36, gap: 20, minHeight: 260, justifyContent: 'center' },
  lesson: { backgroundColor: 'white', padding: 22, borderRadius: 18, borderWidth: 1, borderColor: '#E4E9F2', marginBottom: 16 }, flex: { flex: 1 }, lessonHeading: { flexDirection: 'row', alignItems: 'center', marginBottom: 16 },
  chip: { backgroundColor: '#EEF3FA', color: '#617694', padding: 8, borderRadius: 8, fontSize: 11 }, dayRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20 },
  notice: { backgroundColor: '#FFF6E6', padding: 14, borderRadius: 12, marginBottom: 16, gap: 8 }, noticeText: { color: '#8A6825', fontSize: 12 },
  error: { backgroundColor: '#FFF0EF', padding: 16, borderRadius: 12, marginBottom: 18, gap: 12 }, errorText: { color: '#B33D3D', fontSize: 13, lineHeight: 21 },
  recording: { backgroundColor: '#FFF0F1', padding: 12, borderRadius: 12, marginBottom: 20, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  busy: { position: 'absolute', right: 25, bottom: 20, backgroundColor: 'white', padding: 14, borderRadius: 12, flexDirection: 'row', gap: 10 },
  modalBackdrop: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#14243B66', padding: 20 },
  modal: { backgroundColor: 'white', borderRadius: 20, padding: 26, width: '100%', maxWidth: 420, gap: 16 }, input: { minHeight: 48, borderWidth: 1, borderColor: '#DEE5F0', borderRadius: 12, padding: 14, fontSize: 15 },
});
