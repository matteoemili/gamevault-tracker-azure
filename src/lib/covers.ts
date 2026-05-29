/**
 * Cover art resolution via serial number.
 *
 * Confirmed cover sources (community-maintained GitHub repos by xlenore):
 *   PS1 → https://github.com/xlenore/psx-covers  (covers/default/<SERIAL>.jpg)
 *   PS2 → https://github.com/xlenore/ps2-covers  (covers/default/<SERIAL>.jpg)
 *
 * Images are fetched directly by the browser — nothing is saved locally.
 * For any other platform, buildCoverUrl returns null and the <CoverImage>
 * component shows a neutral placeholder instead.
 *
 * NOTE: If a serial resolves to a 404 (the cover simply isn't in the
 * repository yet) the <CoverImage> component handles that gracefully via its
 * onError → placeholder fallback — no extra logic needed here.
 */

/** Canonical serial form: uppercase, hyphen-separated, e.g. "SCES-00001". */
function normaliseSerial(raw: string): string {
  // Strip surrounding whitespace, uppercase everything.
  const trimmed = raw.trim().toUpperCase();

  // Accept dash-separated (SLUS-20152), underscore-separated (SLUS_20152),
  // or no-separator (SLUS20152) forms and always return the dashed variant.
  const match = trimmed.match(/^([A-Z]{3,4})[_-]?(\d{5,6}[A-Z0-9]*)$/);
  if (match) {
    return `${match[1]}-${match[2]}`;
  }

  // Return the cleaned string as-is if it doesn't match the pattern; the
  // cover lookup will simply return null or fall through to a 404, which the
  // image component handles with the fallback.
  return trimmed;
}

/**
 * URL templates per confirmed platform.
 * Only repos verified to exist under the xlenore GitHub account are listed.
 * PS3 and PSP repos do not exist under this author — those platforms
 * will return null and the caller falls back to the placeholder.
 */
const COVER_URL_TEMPLATES: Record<string, (serial: string) => string> = {
  PS1: (serial) =>
    `https://raw.githubusercontent.com/xlenore/psx-covers/main/covers/default/${serial}.jpg`,
  PS2: (serial) =>
    `https://raw.githubusercontent.com/xlenore/ps2-covers/main/covers/default/${serial}.jpg`,
};

/**
 * Returns a candidate cover-art URL for the given platform + serial, or null
 * when no cover source is available for that platform.
 *
 * @param platform  The game's platform identifier (e.g. "PS2", "PC").
 * @param serial    The raw serial string entered by the user.
 */
export function buildCoverUrl(platform: string, serial: string): string | null {
  const template = COVER_URL_TEMPLATES[platform.toUpperCase()];
  if (!template) return null;

  const normalisedSerial = normaliseSerial(serial);
  if (!normalisedSerial) return null;

  return template(normalisedSerial);
}
