import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Game } from '@/lib/types';
import { PlatformLogo } from './PlatformLogo';
import { PlatformCategory } from './CategoryDialog';
import { Pencil, Trash, Star } from '@phosphor-icons/react';
import { format } from 'date-fns';
import { useTheme } from '@/contexts/theme-context';

interface GameCardProps {
  game: Game;
  onEdit: (game: Game) => void;
  onDelete: (id: string) => void;
  categories: PlatformCategory[];
}

export function GameCard({ game, onEdit, onDelete, categories }: GameCardProps) {
  const { theme } = useTheme();

  const formatPrice = (price: number | undefined) =>
    price === undefined || price === 0 ? 'Untracked' : `£${price.toFixed(2)}`;

  const category = categories.find(c => c.id === game.platform);
  const platformName = category?.name ?? game.platform;

  const statusClass = game.acquired ? 'status-owned' : game.priority ? 'status-priority' : 'status-wanted';

  if (theme === 'neon-arcade') {
    return <NeonCard game={game} onEdit={onEdit} onDelete={onDelete} platformName={platformName} category={category} statusClass={statusClass} />;
  }
  if (theme === 'dashboard-pro') {
    return <CompactCard game={game} onEdit={onEdit} onDelete={onDelete} platformName={platformName} category={category} statusClass={statusClass} formatPrice={formatPrice} />;
  }
  if (theme === 'retro-collector') {
    return <RetroCard game={game} onEdit={onEdit} onDelete={onDelete} platformName={platformName} category={category} statusClass={statusClass} formatPrice={formatPrice} />;
  }
  // clean-minimal default
  return <MinimalCard game={game} onEdit={onEdit} onDelete={onDelete} platformName={platformName} category={category} statusClass={statusClass} formatPrice={formatPrice} />;
}

/* ─── Shared prop type ───────────────────────────────────────── */
interface CardProps {
  game: Game;
  onEdit: (game: Game) => void;
  onDelete: (id: string) => void;
  platformName: string;
  category: PlatformCategory | undefined;
  statusClass: string;
  formatPrice?: (p: number | undefined) => string;
}

/* ─── 1. Clean Minimal ───────────────────────────────────────── */
function MinimalCard({ game, onEdit, onDelete, platformName, category, statusClass, formatPrice }: CardProps) {
  return (
    <Card className={`p-6 game-card ${statusClass}`}>
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-3">
            <PlatformLogo platform={game.platform} size="sm" logoUrl={category?.logoUrl} />
            <span className="text-xs text-muted-foreground font-medium">{platformName}</span>
          </div>
          <h3 className="font-semibold text-base mb-3 leading-snug">{game.name}</h3>
          <div className="flex flex-wrap gap-1.5 mb-3">
            {game.acquired ? (
              <Badge className="bg-indigo-600 text-white dark:bg-indigo-500 dark:text-white">Owned</Badge>
            ) : (
              <Badge className="bg-slate-100 text-slate-700 border border-slate-300 dark:bg-zinc-800 dark:text-zinc-300 dark:border-zinc-600">Wishlist</Badge>
            )}
            {game.priority && !game.acquired && (
              <Badge className="bg-amber-100 text-amber-800 border border-amber-300 dark:bg-amber-900/40 dark:text-amber-300 dark:border-amber-700/50 flex items-center gap-1">
                <Star weight="fill" size={10} /> Priority
              </Badge>
            )}
          </div>
          <div className="text-sm text-muted-foreground space-y-0.5">
            {!game.acquired && game.targetPrice !== undefined && (
              <p>Target: <span className="text-foreground font-medium">£{game.targetPrice.toFixed(2)}</span></p>
            )}
            {game.acquired && (
              <>
                <p>Paid: <span className="text-foreground font-medium">{formatPrice!(game.purchasePrice)}</span></p>
                {game.acquisitionDate && <p>Acquired {format(new Date(game.acquisitionDate), 'MMM d, yyyy')}</p>}
                {game.seller && <p>from {game.seller}</p>}
              </>
            )}
            {game.notes && <p className="mt-2 text-xs italic line-clamp-2">{game.notes}</p>}
          </div>
        </div>
        <div className="flex gap-1.5 flex-shrink-0">
          <Button size="icon" variant="ghost" onClick={() => onEdit(game)} className="h-8 w-8 text-muted-foreground hover:text-foreground">
            <Pencil size={14} />
          </Button>
          <Button size="icon" variant="ghost" onClick={() => onDelete(game.id)} className="h-8 w-8 text-muted-foreground hover:text-destructive">
            <Trash size={14} />
          </Button>
        </div>
      </div>
    </Card>
  );
}

/* ─── 2. Neon Arcade ─────────────────────────────────────────── */
function NeonCard({ game, onEdit, onDelete, platformName, statusClass }: CardProps) {
  const statusColor = game.acquired ? '#4ade80' : game.priority ? '#fb923c' : '#a78bfa';

  return (
    <Card className={`p-5 game-card ${statusClass}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-3">
            <span className="text-primary font-mono text-xs opacity-50">[{platformName.toUpperCase().replace(/\s/g, '_')}]</span>
          </div>
          <h3 className="font-mono font-bold text-sm mb-3 leading-snug" style={{ color: 'var(--primary)' }}>
            <span className="opacity-40 mr-1">&gt;</span>
            {game.name}
          </h3>
          <div className="font-mono text-xs space-y-1" style={{ color: 'var(--muted-foreground)' }}>
            <div className="flex items-center gap-2">
              <span className="opacity-50">STATUS:</span>
              <span style={{ color: statusColor }} className="font-bold">
                {game.acquired ? '✓ ACQUIRED' : game.priority ? '⚡ PRIORITY' : '◈ HUNTING'}
              </span>
            </div>
            {game.acquired && game.purchasePrice !== undefined && (
              <div><span className="opacity-50">COST:</span> <span className="text-primary">£{game.purchasePrice.toFixed(2)}</span></div>
            )}
            {!game.acquired && game.targetPrice !== undefined && (
              <div><span className="opacity-50">BUDGET:</span> <span className="text-primary">£{game.targetPrice.toFixed(2)}</span></div>
            )}
            {game.acquisitionDate && (
              <div><span className="opacity-50">DATE:</span> {format(new Date(game.acquisitionDate), 'yyyy-MM-dd')}</div>
            )}
            {game.seller && (
              <div><span className="opacity-50">SOURCE:</span> {game.seller}</div>
            )}
            {game.notes && (
              <div className="mt-2 opacity-70 italic truncate" title={game.notes}>// {game.notes}</div>
            )}
          </div>
        </div>
        <div className="flex flex-col gap-1.5 flex-shrink-0">
          <Button size="icon" variant="ghost" onClick={() => onEdit(game)} className="h-7 w-7 font-mono text-xs" title="EDIT">
            <Pencil size={13} />
          </Button>
          <Button size="icon" variant="ghost" onClick={() => onDelete(game.id)} className="h-7 w-7 text-destructive" title="DELETE">
            <Trash size={13} />
          </Button>
        </div>
      </div>
    </Card>
  );
}

/* ─── 3. Retro Collector ─────────────────────────────────────── */
function RetroCard({ game, onEdit, onDelete, platformName, category, statusClass, formatPrice }: CardProps) {
  return (
    <Card className={`p-5 game-card ${statusClass}`} style={{ fontFamily: 'Georgia, serif' }}>
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-2" style={{ borderBottom: '1px dashed #c5a572', paddingBottom: '8px' }}>
            <PlatformLogo platform={game.platform} size="sm" logoUrl={category?.logoUrl} />
            <span className="text-xs uppercase tracking-widest font-bold" style={{ color: 'var(--muted-foreground)', fontFamily: 'ui-monospace, monospace' }}>{platformName}</span>
          </div>
          <h3 className="font-bold text-base mb-3 leading-snug tracking-tight">{game.name}</h3>
          <div className="flex flex-wrap gap-2 mb-3">
            <span
              className="text-xs font-black uppercase tracking-widest px-2 py-0.5"
              style={{
                border: `2px solid ${game.acquired ? '#166534' : '#92400e'}`,
                color: game.acquired ? '#166534' : '#92400e',
                borderRadius: '2px',
                fontFamily: 'ui-monospace, monospace',
              }}
            >
              {game.acquired ? '● OWNED' : '○ WANTED'}
            </span>
            {game.priority && !game.acquired && (
              <span className="text-xs font-black uppercase tracking-widest px-2 py-0.5"
                style={{ border: '2px solid #b45309', color: '#b45309', borderRadius: '2px', fontFamily: 'ui-monospace, monospace' }}>
                ★ PRIORITY
              </span>
            )}
          </div>
          <div className="text-sm space-y-0.5" style={{ color: 'var(--muted-foreground)' }}>
            {!game.acquired && game.targetPrice !== undefined && (
              <p>Target Price — <strong>£{game.targetPrice.toFixed(2)}</strong></p>
            )}
            {game.acquired && (
              <>
                <p>Purchase — <strong>{formatPrice!(game.purchasePrice)}</strong></p>
                {game.acquisitionDate && <p>Acquired — {format(new Date(game.acquisitionDate), 'MMMM d, yyyy')}</p>}
                {game.seller && <p>Seller — {game.seller}</p>}
              </>
            )}
            {game.notes && <p className="mt-2 text-xs italic">"{game.notes}"</p>}
          </div>
        </div>
        <div className="flex flex-col gap-1 flex-shrink-0">
          <Button size="icon" variant="outline" onClick={() => onEdit(game)} className="h-7 w-7">
            <Pencil size={13} />
          </Button>
          <Button size="icon" variant="outline" onClick={() => onDelete(game.id)} className="h-7 w-7">
            <Trash size={13} className="text-destructive" />
          </Button>
        </div>
      </div>
    </Card>
  );
}

/* ─── 4. Dashboard Pro ───────────────────────────────────────── */
function CompactCard({ game, onEdit, onDelete, platformName, category, statusClass, formatPrice }: CardProps) {
  const dotColor = game.acquired ? '#10b981' : game.priority ? '#ef4444' : '#f59e0b';

  return (
    <Card className={`game-card ${statusClass}`}>
      <div className="flex items-center gap-3">
        <span
          className="flex-shrink-0 w-2 h-2 rounded-full"
          style={{ backgroundColor: dotColor }}
          title={game.acquired ? 'Owned' : game.priority ? 'Priority' : 'Wanted'}
        />
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-medium text-sm truncate">{game.name}</span>
              </div>
              <div className="flex items-center gap-2 mt-0.5">
                <span className="text-xs font-mono" style={{ color: 'var(--muted-foreground)' }}>{platformName}</span>
                {game.acquired && game.purchasePrice !== undefined && (
                  <span className="text-xs" style={{ color: 'var(--muted-foreground)' }}>· £{game.purchasePrice.toFixed(2)}</span>
                )}
                {!game.acquired && game.targetPrice !== undefined && (
                  <span className="text-xs" style={{ color: 'var(--muted-foreground)' }}>· target £{game.targetPrice.toFixed(2)}</span>
                )}
                {game.acquisitionDate && (
                  <span className="text-xs" style={{ color: 'var(--muted-foreground)' }}>· {format(new Date(game.acquisitionDate), 'dd/MM/yy')}</span>
                )}
              </div>
              {game.notes && <p className="text-xs mt-0.5 truncate italic" style={{ color: 'var(--muted-foreground)' }}>{game.notes}</p>}
            </div>
            <div className="flex items-center gap-1 flex-shrink-0">
              <Button size="icon" variant="ghost" onClick={() => onEdit(game)} className="h-6 w-6">
                <Pencil size={11} />
              </Button>
              <Button size="icon" variant="ghost" onClick={() => onDelete(game.id)} className="h-6 w-6 text-destructive">
                <Trash size={11} />
              </Button>
            </div>
          </div>
        </div>
      </div>
    </Card>
  );
}

