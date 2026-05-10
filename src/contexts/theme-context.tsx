import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react';
import { ThemeName, THEMES } from '@/lib/themes';

const THEME_KEY = 'gamevault-theme';
const DARK_KEY = 'gamevault-dark';

function getInitialTheme(): ThemeName {
  try {
    const stored = localStorage.getItem(THEME_KEY) as ThemeName | null;
    if (stored && THEMES.some(t => t.name === stored)) return stored;
  } catch {}
  return 'clean-minimal';
}

function getInitialDark(theme: ThemeName): boolean {
  try {
    const stored = localStorage.getItem(DARK_KEY);
    if (stored !== null) return stored === 'true';
  } catch {}
  return THEMES.find(t => t.name === theme)?.defaultDark ?? false;
}

interface ThemeContextValue {
  theme: ThemeName;
  isDark: boolean;
  setTheme: (t: ThemeName) => void;
  setDark: (dark: boolean) => void;
  toggleDark: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<ThemeName>(getInitialTheme);
  const [isDark, setIsDarkState] = useState<boolean>(() => getInitialDark(getInitialTheme()));

  const applyToDOM = useCallback((t: ThemeName, dark: boolean) => {
    // Apply to <html> so CSS variables cascade to body/everything
    const html = document.documentElement;
    html.setAttribute('data-theme', t);
    html.classList.toggle('dark', dark);
    html.setAttribute('data-appearance', dark ? 'dark' : 'light');
    // Also set on #root for legacy component-level selectors
    const root = document.getElementById('root');
    if (root) {
      root.setAttribute('data-theme', t);
      root.classList.toggle('dark', dark);
    }
  }, []);

  useEffect(() => {
    applyToDOM(theme, isDark);
  }, [theme, isDark, applyToDOM]);

  const setTheme = useCallback((t: ThemeName) => {
    setThemeState(t);
    try { localStorage.setItem(THEME_KEY, t); } catch {}
    // Auto-switch to dark default when user hasn't set an explicit preference
    const storedDark = localStorage.getItem(DARK_KEY);
    if (storedDark === null) {
      const defaultDark = THEMES.find(th => th.name === t)?.defaultDark ?? false;
      setIsDarkState(defaultDark);
    }
  }, []);

  const setDark = useCallback((dark: boolean) => {
    setIsDarkState(dark);
    try { localStorage.setItem(DARK_KEY, String(dark)); } catch {}
  }, []);

  const toggleDark = useCallback(() => {
    setIsDarkState(prev => {
      const next = !prev;
      try { localStorage.setItem(DARK_KEY, String(next)); } catch {}
      return next;
    });
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, isDark, setTheme, setDark, toggleDark }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within a ThemeProvider');
  return ctx;
}
