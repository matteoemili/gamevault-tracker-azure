export type Platform = 'PS1' | 'PS2' | 'PS3' | 'PSP' | 'PC';

export interface Game {
  id: string;
  name: string;
  platform: Platform;
  acquired: boolean;
  targetPrice?: number;
  priority?: boolean;
  purchasePrice?: number;
  acquisitionDate?: string;
  seller?: string;
  notes?: string;
}

export const PLATFORM_LOGOS: Record<Platform, string> = {
  PS1: 'https://upload.wikimedia.org/wikipedia/commons/4/4e/Playstation_logo_colour.svg',
  PS2: 'https://upload.wikimedia.org/wikipedia/commons/thumb/7/76/PlayStation_2_logo.svg/500px-PlayStation_2_logo.svg.png',
  PS3: 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/PlayStation_3_logo_%282009%29.svg/500px-PlayStation_3_logo_%282009%29.svg.png',
  PSP: 'https://upload.wikimedia.org/wikipedia/commons/0/0e/PSP_Logo.svg',
  PC: 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/38/Pc_game_logo.png/600px-Pc_game_logo.png'
};

export const PLATFORM_NAMES: Record<Platform, string> = {
  PS1: 'PlayStation',
  PS2: 'PlayStation 2',
  PS3: 'PlayStation 3',
  PSP: 'PlayStation Portable',
  PC: 'PC'
};
