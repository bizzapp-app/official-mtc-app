import { CONFIG } from './config.js';

export function getTheme() {
  try { return localStorage.getItem(CONFIG.STORAGE_KEYS.THEME_MODE) || 'light'; }
  catch (_) { return 'light'; }
}

export function applyTheme(theme = getTheme()) {
  const normalized = theme === 'dark' ? 'dark' : 'light';
  document.documentElement.dataset.theme = normalized;
  if (document.body) document.body.classList.toggle('dark-mode', normalized === 'dark');
  return normalized;
}

export function toggleTheme() {
  const next = getTheme() === 'dark' ? 'light' : 'dark';
  try { localStorage.setItem(CONFIG.STORAGE_KEYS.THEME_MODE, next); } catch (_) {}
  applyTheme(next);
  return next;
}

applyTheme();
