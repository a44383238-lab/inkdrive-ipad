/** @param {string} value */
export function cleanName(value) {
  const name = value.trim();
  if (!name || name === '.' || name === '..' || /[<>:"/\\|?*\x00-\x1f]/u.test(name) ||
      /[. ]$/u.test(name) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/iu.test(name) || name.length > 120) {
    throw new Error('이름은 1~120자이며 파일 경로·예약 이름·특수문자를 포함할 수 없어요.');
  }
  return name;
}
/** @param {string} parent @param {string} name */
export function relativePath(parent, name) {
  if (parent) parent.split('/').forEach(part => {
    if (cleanName(part) !== part) throw new Error('잘못된 폴더 경로예요.');
  });
  return [parent, cleanName(name)].filter(Boolean).join('/');
}
/** @template {{name:string, directory:boolean}} T @param {T[]} entries @param {string} search */
export function orderedEntries(entries, search = '') {
  const query = search.trim().toLocaleLowerCase();
  return entries.filter(e => e.name.toLocaleLowerCase().includes(query)).sort((a, b) =>
    Number(b.directory) - Number(a.directory) || a.name.localeCompare(b.name, 'ko', { numeric: true, sensitivity: 'base' }));
}
export class SingleFlight {
  /** @type {Promise<unknown> | undefined} */
  pending;
  /** @template T @param {() => Promise<T>} task @returns {Promise<T>} */
  run(task) {
    if (this.pending) return /** @type {Promise<T>} */ (this.pending);
    const result = Promise.resolve().then(task);
    this.pending = result;
    void result.then(() => { this.pending = undefined; }, () => { this.pending = undefined; });
    return result;
  }
}
export class LatestRequest {
  generation = 0;
  /** @template T @param {() => Promise<T>} task @param {(value:T) => void} apply */
  async run(task, apply) {
    const request = ++this.generation;
    const value = await task();
    if (request === this.generation) apply(value);
  }
}
/** @param {string} current @param {string} next */
export function folderDestination(current, next) {
  if (next) next.split('/').forEach(part => {
    if (cleanName(part) !== part) throw new Error('잘못된 폴더 경로예요.');
  });
  return { path: next, changed: current !== next };
}
/** @param {string} path */
export function parentFolder(path) {
  folderDestination('', path);
  return path.split('/').slice(0, -1).join('/');
}
