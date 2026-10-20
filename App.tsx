import React, { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useWindowDimensions } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { Native, type Entry, type Lesson } from './modules/inkdrive';
import { cleanName, orderedEntries, SingleFlight, LatestRequest } from './src/domain.mjs';

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
    }, ({ selected, entries, daily }) => { setRoot(selected?.name ?? null); setRows(entries); setLessons(daily); });
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
  const changeFolder = (next: string) => { setRows([]); setPath(next); setQuery(''); };
  const button = (label: string, action: () => void, secondary = false, disabled = false) => (
    <Pressable accessibilityRole="button" disabled={busy || disabled} onPress={action}
      style={({ pressed }) => [styles.button, secondary && styles.secondary, (busy || disabled) && styles.disabled, pressed && styles.pressed]}>
      <Text style={[styles.buttonText, secondary && styles.secondaryText]}>{label}</Text>
    </Pressable>
  );
  return <SafeAreaView style={[styles.app, compact && { flexDirection: 'column' }]}>
    <StatusBar style="dark" />
    <View style={[styles.sidebar, compact && { width: '100%', flexDirection: 'row', flexWrap: 'wrap', padding: 10 }]}>
      <Text style={[styles.wordmark, compact && { width: '100%', fontSize: 23, padding: 5 }]}>InkDrive<Text style={styles.dot}>.</Text></Text>
      {!compact && <Text style={styles.caption}>수업은 이어지고,{ '\n' }자료는 한곳에.</Text>}
      {(['library', 'today', 'settings'] as Screen[]).map((key, i) => <Pressable key={key} accessibilityRole="tab"
        accessibilityState={{ selected: screen === key }} onPress={() => setScreen(key)} style={[styles.nav, compact && { flex: 1 }, screen === key && styles.navSelected]}>
        <Text style={[styles.navText, screen === key && styles.navTextSelected]}>{['▤  내 서재', '◷  오늘 수업', '⚙  연결·설정'][i]}</Text>
      </Pressable>)}
      {!compact && <View style={styles.sidebarBottom}><Text style={styles.eyebrow}>AI STUDY ROUTINE</Text><Text style={styles.clock}>매일 밤 10:00</Text><Text style={styles.small}>전사 · 강의노트 · 복습문제</Text></View>}
    </View>
    <View style={styles.main}>
      <ScrollView contentContainerStyle={[styles.content, compact && { padding: 20 }]} keyboardShouldPersistTaps="handled">
        {!Native && <View style={styles.notice}><Text style={styles.noticeText}>화면 미리보기 · 실제 필기와 iCloud 연결은 Swift 모듈이 포함된 개발용 앱에서 사용할 수 있어요.</Text></View>}
        {error ? <View style={styles.error}><Text selectable style={styles.errorText}>{error}</Text>{button('다시 확인', () => void run(() => refresh()), true)}</View> : null}
        {recording.active && <View style={styles.recording}><Text style={styles.errorText}>● 수업 녹음 중 · {Math.floor(recording.seconds / 60)}분 {Math.floor(recording.seconds % 60)}초</Text>
          {button('녹음 종료·연결', () => void run(async () => { await Native?.stopRecording(); await refresh(); }), true)}</View>}
        {recording.error && <Text style={styles.errorText}>{recording.error}</Text>}
        {recording.pending && !recording.active && <View style={styles.notice}><Text style={styles.noticeText}>수업에 아직 연결하지 못한 녹음이 있어요. 원음 파일은 보존돼 있어요.</Text>
          {button('녹음 복구·다시 연결', () => void run(async () => { await Native?.recoverRecording(); await refresh(); }), true)}</View>}
        {recording.pending && !recording.active && button('복구 대기 녹음을 보존하고 새 녹음 준비', () => void run(async () => { await Native?.archivePendingRecording(); await refresh(); }), true)}
        {screen === 'library' && <>
          <Text style={styles.eyebrow}>YOUR CLASSROOM, CONNECTED</Text>
          <Text style={styles.title}>내 서재</Text>
          <Text style={styles.subtitle}>필기한 그 PDF를, 노트북에서도 그대로.</Text>
          <View style={styles.actions}>
            {button('＋ 새 노트', () => openForm('note'), false, !root)}
            {button('새 폴더', () => openForm('folder'), true, !root)}
            {button('외부 PDF 원본 열기', () => void run(async () => { await Native?.pickPDF(); await refresh(); }), true, !Native)}
          </View>
          {!root ? <View style={styles.empty}>
            <Text style={styles.emptyIcon}>▱</Text><Text style={styles.sectionTitle}>iCloud에 서재를 만들어 주세요</Text>
            <Text style={styles.body}>iCloud Drive의 InkDrive 폴더를 선택하면 필기 PDF와 수업 녹음이 Windows로 이어져요.</Text>
            {button('서재 폴더 연결', () => void run(async () => { const selected = await Native?.pickFolder(); if (selected) { setPath(''); await refresh(''); } }), false, !Native)}
          </View> : <>
            <View style={styles.breadcrumb}><Pressable onPress={() => changeFolder('')}><Text style={styles.link}>{root}</Text></Pressable>
              {path.split('/').filter(Boolean).map((part, i, parts) => <Pressable key={i} onPress={() => changeFolder(parts.slice(0, i + 1).join('/'))}><Text style={styles.link}> / {part}</Text></Pressable>)}
            </View>
            <TextInput accessibilityLabel="파일 검색" style={styles.search} placeholder="이 폴더에서 검색" value={query} onChangeText={setQuery} />
            <View style={styles.tableHeader}><Text style={styles.small}>이름</Text><Text style={styles.small}>원본 파일</Text></View>
            {orderedEntries(rows, query).map(row => <View key={row.path} style={styles.fileRow}>
              <Pressable disabled={busy} style={styles.fileName} onPress={() => row.directory ? changeFolder(row.path) : void run(async () => {
                if (row.path.toLowerCase().endsWith('.pdf')) await Native!.openEditor(row.path);
                else setResultText({ title: row.name, text: await Native!.readText(row.path) });
                await refresh();
              })}>
                <Text style={styles.fileIcon}>{row.directory ? '▱' : '▤'}</Text><View style={styles.flex}><Text style={styles.fileTitle}>{row.name}</Text>
                  <Text style={styles.small}>{row.directory ? '폴더' : `${Math.max(1, Math.round(row.bytes / 1024))} KB · ${row.path.split('.').at(-1)?.toUpperCase()}`}</Text></View>
              </Pressable>
              {!row.directory && row.path.toLowerCase().endsWith('.pdf') && button('수업 연결', () => openForm('lesson', row.path), true)}
            </View>)}
            {rows.length === 0 && <Text style={styles.body}>아직 파일이 없어요. 새 노트를 만들어 첫 수업을 시작해 보세요.</Text>}
          </>}
          <View style={styles.hint}><Text style={styles.hintTitle}>한 수업, 하나의 흐름</Text><Text style={styles.body}>PDF에 ‘수업 연결’을 누르고 녹음을 시작하세요. 수업이 끝나면 밤 10시 AI 처리를 위한 자료 목록이 준비돼요.</Text></View>
        </>}
        {screen === 'today' && <>
          <Text style={styles.eyebrow}>{date} · ASIA/SEOUL</Text><Text style={styles.title}>오늘 수업</Text>
          <Text style={styles.subtitle}>낮에는 수업에 집중하고, 밤에는 다시 이해하기.</Text>
          <View style={styles.routine}><Text style={styles.sectionTitle}>22:00  수업 자료 확인</Text><Text style={styles.body}>녹음 전사 → PDF와 대조한 상세 강의노트 → 해설이 있는 복습문제</Text>
            <Text style={styles.small}>처리 PC가 켜져 있고 iCloud 동기화가 끝나 있어야 해요. ‘수업 종료’는 AI 준비 표시이며 처리 완료를 뜻하지 않아요.</Text>
            {button('AI 결과 폴더 보기', () => { setScreen('library'); changeFolder('AI'); }, true, !root)}</View>
          {!lessons.length && <View style={styles.empty}><Text style={styles.sectionTitle}>연결된 수업이 없어요</Text><Text style={styles.body}>내 서재에서 PDF를 고른 뒤 ‘수업 연결’을 눌러 주세요.</Text>{button('서재로 이동', () => setScreen('library'), true)}</View>}
          {lessons.map(lesson => <View key={lesson.id} style={styles.lesson}>
            <Text style={styles.eyebrow}>{lesson.subject}</Text><Text style={styles.sectionTitle}>{lesson.title}</Text><Text style={styles.small}>{lesson.pdf}</Text>
            <View style={styles.chips}><Text style={styles.chip}>{lesson.endedAt ? '수업 종료됨' : '수업 진행 중'}</Text><Text style={styles.chip}>녹음 {lesson.recordings.length}개</Text></View>
            <View style={styles.actions}>
              {button('필기 열기', () => void run(async () => { await Native!.openEditor(lesson.pdf); await refresh(); }), true)}
              {button('녹음 시작', () => void run(async () => { await Native!.startRecording(JSON.stringify(lesson)); setRecording(await Native!.recordingStatus()); }), true, recording.active || !!lesson.endedAt)}
              {button('기존 녹음 가져오기', () => void run(async () => { await Native!.importRecording(JSON.stringify(lesson)); await refresh(); }), true, recording.active)}
              {button(lesson.endedAt ? '수업 다시 열기' : '수업 종료', () => void run(async () => {
                if (recording.active) throw new Error('먼저 녹음을 종료해 주세요.');
                await Native!.saveLesson(JSON.stringify({ ...lesson, endedAt: lesson.endedAt ? null : new Date().toISOString() })); await refresh();
              }), false, recording.active)}
            </View><Text style={styles.small}>녹음 가져오기는 원음을 서재의 Recordings 폴더에 복사해 연결해요.</Text>
          </View>)}
        </>}
        {screen === 'settings' && <>
          <Text style={styles.eyebrow}>EVERYTHING IN ITS PLACE</Text><Text style={styles.title}>연결·설정</Text>
          <View style={styles.lesson}><Text style={styles.sectionTitle}>서재 위치</Text><Text style={styles.body}>{root ?? '아직 연결하지 않았어요'}</Text>
            {button('iCloud Drive 폴더 선택', () => void run(async () => { if (await Native?.pickFolder()) { setPath(''); await refresh(''); } }), true, !Native || recording.active)}
            <Text style={styles.small}>Windows에서는 iCloud Drive의 같은 InkDrive 폴더를 사용하세요. 파일 선택 권한이 만료되면 이곳에서 다시 연결할 수 있어요.</Text></View>
          <View style={styles.lesson}><Text style={styles.sectionTitle}>필기 도구</Text><Text style={styles.body}>도구별 색상·굵기·불투명도와 즐겨찾기는 필기 화면에서 설정하고 기기에 기억해요. Pencil 측면 더블 탭은 시스템 설정을 따르고, 두 손가락 더블 탭은 실행 취소예요.</Text></View>
          <View style={styles.lesson}><Text style={styles.sectionTitle}>저녁 학습 자동화</Text><Text style={styles.body}>매일 오후 10시 · 한국 시간</Text><Text style={styles.small}>AI 실행은 Windows의 Codex 예약 작업이 담당해요. iPad 앱 자체가 백그라운드에서 AI를 계속 실행하지는 않아요. 결과는 서재의 AI 폴더에 저장하도록 구성해요.</Text></View>
          <Text style={styles.small}>InkDrive 0.1 · {Platform.OS} · 원본 PDF에 저장</Text>
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
        <Text style={styles.sectionTitle}>{resultText?.title}</Text>{button('닫기', () => setResultText(null), true)}
        <ScrollView style={{ marginTop: 20 }}><Text selectable style={[styles.body, { color: '#263B5A' }]}>{resultText?.text}</Text></ScrollView>
      </SafeAreaView>
    </Modal>
  </SafeAreaView>;
}
export default function App() { return <SafeAreaProvider><LibraryApp /></SafeAreaProvider>; }

const styles = StyleSheet.create({
  app: { flex: 1, flexDirection: 'row', backgroundColor: '#FAFBFD' },
  sidebar: { width: 205, backgroundColor: '#F0F3F9', padding: 22, borderRightWidth: 1, borderRightColor: '#E3E8F1' },
  wordmark: { fontSize: 28, fontWeight: '800', color: '#152442', letterSpacing: -1 }, dot: { color: '#3865DD' },
  caption: { fontSize: 13, color: '#738099', lineHeight: 21, marginTop: 15, marginBottom: 44 },
  nav: { padding: 13, borderRadius: 10, marginBottom: 8 }, navSelected: { backgroundColor: '#DFE8FC' },
  navText: { color: '#63708A', fontSize: 14 }, navTextSelected: { color: '#2455D6', fontWeight: '700' },
  sidebarBottom: { marginTop: 'auto', paddingTop: 28 }, clock: { color: '#233B65', fontWeight: '700', fontSize: 17, marginVertical: 9 },
  main: { flex: 1 }, content: { padding: 38, maxWidth: 1200, width: '100%', alignSelf: 'center', paddingBottom: 80 },
  eyebrow: { fontSize: 10, fontWeight: '700', letterSpacing: 1.5, color: '#6A7C9C', marginBottom: 10 },
  title: { fontSize: 34, fontWeight: '700', color: '#172A48', letterSpacing: -1 }, subtitle: { color: '#78869C', fontSize: 15, lineHeight: 24, marginTop: 9, marginBottom: 26 },
  sectionTitle: { fontSize: 19, fontWeight: '700', color: '#223958', marginBottom: 9 },
  body: { fontSize: 14, color: '#66758D', lineHeight: 24, marginBottom: 12 }, small: { fontSize: 12, color: '#8490A4', lineHeight: 20 },
  button: { paddingHorizontal: 17, paddingVertical: 11, backgroundColor: '#2455D6', borderRadius: 9, alignItems: 'center' },
  secondary: { backgroundColor: '#EDF1F9' }, buttonText: { fontSize: 13, fontWeight: '600', color: 'white' }, secondaryText: { color: '#49607F' },
  disabled: { opacity: 0.45 }, pressed: { opacity: 0.7 }, actions: { flexDirection: 'row', flexWrap: 'wrap', gap: 9, marginVertical: 14 },
  notice: { backgroundColor: '#FFF6DF', padding: 14, borderRadius: 10, marginBottom: 24 }, noticeText: { color: '#8A6825', fontSize: 12, lineHeight: 20 },
  empty: { marginVertical: 22, alignItems: 'center', padding: 30, backgroundColor: '#FFFFFF', borderRadius: 16, borderWidth: 1, borderColor: '#E5EAF2', gap: 8 },
  emptyIcon: { fontSize: 58, color: '#98B3EF', marginBottom: 12 },
  hint: { backgroundColor: '#F0F4FC', padding: 24, borderRadius: 14, marginTop: 30 }, hintTitle: { fontSize: 15, fontWeight: '700', color: '#42618F', marginBottom: 8 },
  breadcrumb: { flexDirection: 'row', flexWrap: 'wrap', marginTop: 22, marginBottom: 15 }, link: { color: '#4266A1', fontSize: 13, lineHeight: 25 },
  search: { borderWidth: 1, borderColor: '#E2E7F1', backgroundColor: 'white', padding: 13, borderRadius: 10, fontSize: 14, marginBottom: 20 },
  tableHeader: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#E2E7F1' },
  fileRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: '#EDF0F5', gap: 16 },
  fileName: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 16 }, flex: { flex: 1 }, fileIcon: { fontSize: 32, color: '#7999D1' }, fileTitle: { color: '#2D425F', fontWeight: '600', fontSize: 15, marginBottom: 5 },
  routine: { backgroundColor: '#EAF0FD', padding: 24, borderRadius: 14, marginBottom: 20 }, lesson: { backgroundColor: 'white', padding: 23, borderRadius: 14, borderWidth: 1, borderColor: '#E4E9F2', marginBottom: 16 },
  chips: { flexDirection: 'row', gap: 8, marginTop: 12 }, chip: { backgroundColor: '#EFF3F9', color: '#657C9A', padding: 9, borderRadius: 7, fontSize: 12 },
  error: { backgroundColor: '#FFF0EF', padding: 16, borderRadius: 10, marginBottom: 18, gap: 12 }, errorText: { color: '#B33D3D', fontSize: 13, lineHeight: 21 },
  recording: { backgroundColor: '#FFF0EF', padding: 14, borderRadius: 10, marginBottom: 20, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  busy: { position: 'absolute', right: 25, bottom: 20, backgroundColor: 'white', padding: 14, borderRadius: 10, flexDirection: 'row', gap: 10 },
  modalBackdrop: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#14243B77', padding: 20 },
  modal: { backgroundColor: 'white', borderRadius: 18, padding: 28, width: '100%', maxWidth: 450, gap: 12 }, input: { borderWidth: 1, borderColor: '#DEE5F0', borderRadius: 9, padding: 14, fontSize: 15 },
});
