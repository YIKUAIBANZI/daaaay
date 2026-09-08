const timestamp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$/;
export function validateSchedule(value) {
  if (!value || value.version !== 1 || !Array.isArray(value.windows) || value.windows.length > 1000)
    throw new Error('日程格式无效');
  const ids = new Set();
  const windows = value.windows.map(w => {
    if (!w || typeof w.id !== 'string' || !w.id || ids.has(w.id) ||
        !timestamp.test(w.start) || !timestamp.test(w.end) ||
        !Number.isFinite(Date.parse(w.start)) || !Number.isFinite(Date.parse(w.end)) ||
        Date.parse(w.end) <= Date.parse(w.start)) throw new Error('日程 ID 或起止时间无效');
    ids.add(w.id);
    return {id:w.id, start:w.start, end:w.end};
  });
  return {version:1, windows};
}
export function activeWindows(plan, now) {
  return plan.windows.filter(w => Date.parse(w.start) <= now && now < Date.parse(w.end));
}
export function nextBoundary(plan, now) {
  const future = plan.windows.flatMap(w => [Date.parse(w.start),Date.parse(w.end)]).filter(t => t > now);
  return future.length ? Math.min(...future) : null;
}
export function blockingRules(active) {
  return active ? [{id:1, priority:1, action:{type:'block'}, condition:{requestDomains:['douyin.com'],resourceTypes:['main_frame','sub_frame','stylesheet','script','image','font','object','xmlhttprequest','ping','csp_report','media','websocket','webtransport','webbundle','other']}}] : [];
}
