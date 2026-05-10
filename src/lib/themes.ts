export type ThemeName =
  | 'clean-minimal'
  | 'neon-arcade'
  | 'retro-collector'
  | 'dashboard-pro';

export interface ThemeConfig {
  name: ThemeName;
  label: string;
  emoji: string;
  description: string;
  defaultDark: boolean;
}

export const THEMES: ThemeConfig[] = [
  {
    name: 'clean-minimal',
    label: 'Clean Minimal',
    emoji: '🌿',
    description: 'Light, airy & professional',
    defaultDark: false,
  },
  {
    name: 'neon-arcade',
    label: 'Neon Arcade',
    emoji: '🎮',
    description: 'Dark cyberpunk with neon glow',
    defaultDark: true,
  },
  {
    name: 'retro-collector',
    label: 'Retro Collector',
    emoji: '🟠',
    description: 'Warm amber vintage catalog',
    defaultDark: false,
  },
  {
    name: 'dashboard-pro',
    label: 'Dashboard Pro',
    emoji: '🖤',
    description: 'Dark slate with teal accents',
    defaultDark: true,
  },
];
