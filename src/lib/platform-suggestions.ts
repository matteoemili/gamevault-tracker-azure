export interface PlatformSuggestions {
  topRated: string[];
  mostCollectible: string[];
}

export const PLATFORM_SUGGESTIONS: Record<string, PlatformSuggestions> = {
  PS1: {
    topRated: [
      'Final Fantasy VII',
      'Metal Gear Solid',
      'Castlevania: Symphony of the Night',
      'Resident Evil 2',
      'Crash Bandicoot 2: Cortex Strikes Back',
    ],
    mostCollectible: [
      'Suikoden II',
      'Castlevania: Symphony of the Night',
      'Final Fantasy Tactics',
      'Vagrant Story',
      'Xenogears',
    ],
  },
  PS2: {
    topRated: [
      'Shadow of the Colossus',
      'Grand Theft Auto: San Andreas',
      'God of War II',
      'Metal Gear Solid 3: Snake Eater',
      'Final Fantasy XII',
    ],
    mostCollectible: [
      'Haunting Ground',
      'Rule of Rose',
      'Kuon',
      'Ico',
      'Shadow of the Colossus',
    ],
  },
  PS3: {
    topRated: [
      'The Last of Us',
      'Uncharted 2: Among Thieves',
      'Red Dead Redemption',
      'Batman: Arkham City',
      'Metal Gear Solid 4: Guns of the Patriots',
    ],
    mostCollectible: [
      'Demon\'s Souls',
      'Folklore',
      '3D Dot Game Heroes',
      'Valkyria Chronicles',
      'Disgaea 3: Absence of Justice',
    ],
  },
  PSP: {
    topRated: [
      'God of War: Chains of Olympus',
      'Crisis Core: Final Fantasy VII',
      'Persona 3 Portable',
      'Metal Gear Solid: Peace Walker',
      'Tactics Ogre: Let Us Cling Together',
    ],
    mostCollectible: [
      'Valkyria Chronicles II',
      'Tactics Ogre: Let Us Cling Together',
      'Phantasy Star Portable 2 Infinity',
      'Lunar: Silver Star Harmony',
      'Persona 3 Portable',
    ],
  },
  PC: {
    topRated: [
      'Half-Life 2',
      'Portal 2',
      'The Witcher 3: Wild Hunt',
      'Baldur\'s Gate 3',
      'Disco Elysium',
    ],
    mostCollectible: [
      'Half-Life 2',
      'Deus Ex',
      'System Shock 2',
      'Planescape: Torment',
      'Thief: The Dark Project',
    ],
  },
  XBOX: {
    topRated: [
      'Halo: Combat Evolved',
      'Ninja Gaiden',
      'Star Wars: Knights of the Old Republic',
      'Panzer Dragoon Orta',
      'Jet Set Radio Future',
    ],
    mostCollectible: [
      'Panzer Dragoon Orta',
      'Jet Set Radio Future',
      'Metal Wolf Chaos',
      'Otogi: Myth of Demons',
      'Ninja Gaiden',
    ],
  },
};
