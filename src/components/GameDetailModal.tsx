import { format } from 'date-fns';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { CoverImage } from './CoverImage';
import { PlatformLogo } from './PlatformLogo';
import { PlatformCategory } from './CategoryDialog';
import { Game } from '@/lib/types';
import { Star } from '@phosphor-icons/react';

interface GameDetailModalProps {
  /** The game to display, or null when the modal is closed. */
  game: Game | null;
  /** Called when the modal requests to close. */
  onClose: () => void;
  /** Platform categories list, used to resolve the human-readable platform name and logo. */
  categories: PlatformCategory[];
}

/**
 * Read-only detail overlay triggered by clicking a game cover.
 * Shows a large cover on the left and the full game record on the right.
 */
export function GameDetailModal({ game, onClose, categories }: GameDetailModalProps) {
  // Render nothing when no game is selected — Dialog handles its own open state.
  if (!game) return null;

  const category = categories.find(c => c.id === game.platform);
  const platformName = category?.name ?? game.platform;

  // Use loose equality so null from Azure JSON round-trips is treated as unset.
  const formatPrice = (price: number | undefined | null) =>
    price == null || price === 0 ? 'Untracked' : `£${price.toFixed(2)}`;

  return (
    <Dialog open={!!game} onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent className="max-w-2xl p-0 overflow-hidden">
        <div className="flex flex-col sm:flex-row">

          {/* ── Left: large cover ──────────────────────────────── */}
          <div className="sm:w-56 flex-shrink-0 bg-muted/40 flex items-center justify-center p-6">
            <CoverImage
              platform={game.platform}
              serial={game.serial}
              alt={`${game.name} cover`}
              className="w-full max-w-[160px] sm:max-w-none rounded shadow-lg"
              style={{ aspectRatio: '2/3', objectFit: 'cover' }}
            />
          </div>

          {/* ── Right: details ─────────────────────────────────── */}
          <div className="flex-1 p-6 overflow-y-auto">
            <DialogHeader className="mb-4">
              {/* Platform row */}
              <div className="flex items-center gap-2 mb-1">
                <PlatformLogo platform={game.platform} size="sm" logoUrl={category?.logoUrl} />
                <span className="text-xs text-muted-foreground font-medium">{platformName}</span>
              </div>
              <DialogTitle className="text-xl leading-snug">{game.name}</DialogTitle>
            </DialogHeader>

            {/* Status badges */}
            <div className="flex flex-wrap gap-1.5 mb-5">
              {game.acquired ? (
                <Badge className="bg-indigo-600 text-white dark:bg-indigo-500">Owned</Badge>
              ) : (
                <Badge variant="outline">Wishlist</Badge>
              )}
              {game.priority && !game.acquired && (
                <Badge className="bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-900/40 dark:text-amber-300 dark:border-amber-700/50 flex items-center gap-1">
                  <Star weight="fill" size={10} /> Priority
                </Badge>
              )}
            </div>

            {/* Detail rows */}
            <dl className="space-y-2 text-sm">

              {game.serial && (
                <Row label="Serial">{game.serial.toUpperCase()}</Row>
              )}

              {game.acquired && (
                <Row label="Purchase price">{formatPrice(game.purchasePrice)}</Row>
              )}

              {!game.acquired && game.targetPrice != null && (
                <Row label="Target price">£{game.targetPrice.toFixed(2)}</Row>
              )}

              {game.acquisitionDate && (
                <Row label="Acquired">
                  {format(new Date(game.acquisitionDate), 'MMMM d, yyyy')}
                </Row>
              )}

              {game.seller && (
                <Row label="Seller">{game.seller}</Row>
              )}

              {game.notes && (
                <div className="pt-2">
                  <dt className="text-xs font-medium text-muted-foreground mb-1 uppercase tracking-wide">Notes</dt>
                  <dd className="text-foreground whitespace-pre-wrap rounded bg-muted/50 p-3 text-sm leading-relaxed">
                    {game.notes}
                  </dd>
                </div>
              )}

            </dl>
          </div>

        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Simple label/value row used inside the detail panel. */
function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3">
      <dt className="w-32 flex-shrink-0 text-xs font-medium text-muted-foreground uppercase tracking-wide pt-0.5">
        {label}
      </dt>
      <dd className="text-foreground font-medium">{children}</dd>
    </div>
  );
}
