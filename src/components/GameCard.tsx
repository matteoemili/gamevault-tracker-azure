import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Game } from '@/lib/types';
import { PlatformLogo } from './PlatformLogo';
import { Pencil, Trash, Star } from '@phosphor-icons/react';
import { format } from 'date-fns';

interface GameCardProps {
  game: Game;
  onEdit: (game: Game) => void;
  onDelete: (id: string) => void;
}

export function GameCard({ game, onEdit, onDelete }: GameCardProps) {
  const formatPrice = (price: number | undefined) => {
    if (price === undefined || price === 0) {
      return 'Untracked';
    }
    return `$${price.toFixed(2)}`;
  };

  return (
    <Card className="p-6 hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <h3 className="font-medium text-base mb-2 break-words">{game.name}</h3>
          
          <div className="flex flex-wrap gap-2 mb-3">
            {game.acquired ? (
              <Badge className="bg-primary text-primary-foreground">Owned</Badge>
            ) : (
              <Badge className="bg-secondary text-muted-foreground">Wanted</Badge>
            )}
            {game.priority && !game.acquired && (
              <Badge className="bg-accent text-accent-foreground flex items-center gap-1">
                <Star weight="fill" size={12} />
                Priority
              </Badge>
            )}
          </div>

          <div className="text-sm space-y-1 text-muted-foreground">
            {!game.acquired && game.targetPrice !== undefined && (
              <div>Target Price: ${game.targetPrice.toFixed(2)}</div>
            )}
            
            {game.acquired && (
              <>
                <div>Purchase Price: {formatPrice(game.purchasePrice)}</div>
                {game.acquisitionDate && (
                  <div>Acquired: {format(new Date(game.acquisitionDate), 'MMM d, yyyy')}</div>
                )}
                {game.seller && <div>Seller: {game.seller}</div>}
              </>
            )}
            
            {game.notes && (
              <div className="mt-2 text-foreground">
                <span className="font-medium">Notes:</span> {game.notes}
              </div>
            )}
          </div>
        </div>

        <div className="flex flex-col items-center gap-3 flex-shrink-0">
          <PlatformLogo platform={game.platform} size="md" />
          <div className="flex gap-2">
            <Button
              size="icon"
              variant="outline"
              onClick={() => onEdit(game)}
            >
              <Pencil />
            </Button>
            <Button
              size="icon"
              variant="outline"
              onClick={() => onDelete(game.id)}
            >
              <Trash className="text-destructive" />
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}
