import { useState, CSSProperties } from 'react';
import { buildCoverUrl } from '@/lib/covers';
import placeholderSrc from '@/assets/cover-placeholder.svg';

interface CoverImageProps {
  platform: string;
  /** Optional serial number used to resolve the cover URL. */
  serial?: string;
  /** Accessible alt text for the image. */
  alt: string;
  className?: string;
  /** Additional inline styles merged with the base objectFit/display rules. */
  style?: CSSProperties;
  /** Optional click handler — used to open the game detail modal. */
  onClick?: () => void;
}

/**
 * Displays a game cover image resolved from the given platform serial, or a
 * neutral placeholder when:
 *  - no serial is provided,
 *  - the platform has no supported cover repository,
 *  - the HTTP request returns a 404 or any other error.
 *
 * The browser handles caching via normal HTTP semantics — no extra fetch logic
 * is required here.  The <img> element is used (not a <fetch> call) so that
 * requests to third-party image repos don't trigger CORS preflight issues.
 */
export function CoverImage({ platform, serial, alt, className, style, onClick }: CoverImageProps) {
  // Start in the error state when no serial or no matching URL template exists.
  const candidateUrl = serial ? buildCoverUrl(platform, serial) : null;
  const [imgSrc, setImgSrc] = useState<string>(candidateUrl ?? placeholderSrc);
  const [hasError, setHasError] = useState<boolean>(!candidateUrl);

  const handleError = () => {
    // Swap to the placeholder once — prevents an infinite error loop if the
    // placeholder itself were somehow broken.
    if (!hasError) {
      setHasError(true);
      setImgSrc(placeholderSrc);
    }
  };

  return (
    <img
      src={imgSrc}
      alt={alt}
      loading="lazy"
      onError={handleError}
      className={className}
      onClick={onClick}
      // Show the serial as a tooltip so users can verify what was used.
      title={serial ? `Serial: ${serial}` : 'No serial — showing placeholder'}
      // Merge caller-provided styles with the base rules so e.g. RetroCard's
      // border treatment is applied alongside the required objectFit/display.
      style={{ objectFit: 'cover', display: 'block', ...style }}
    />
  );
}
