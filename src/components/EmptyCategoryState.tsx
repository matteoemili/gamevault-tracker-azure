import { Button } from '@/components/ui/button';
import { Plus } from '@phosphor-icons/react';
import { PLATFORM_SUGGESTIONS } from '@/lib/platform-suggestions';

interface EmptyCategoryStateProps {
  platformId: string;
  platformName: string;
  onAddGame: () => void;
}

export function EmptyCategoryState({ platformId, platformName, onAddGame }: EmptyCategoryStateProps) {
  const suggestions = PLATFORM_SUGGESTIONS[platformId.toUpperCase()];

  return (
    <div className="max-w-lg mx-auto text-center py-12">
      <h2 className="text-2xl font-semibold mb-2">No {platformName} Games Yet</h2>
      <p className="text-muted-foreground mb-6">
        Start tracking your {platformName} collection by adding your first game.
      </p>

      {suggestions && (
        <div className="text-left mb-8 flex flex-col sm:flex-row gap-8">
          <div className="flex-1">
            <h3 className="text-xs font-semibold mb-3 text-muted-foreground uppercase tracking-wide">
              Top Rated
            </h3>
            <ul className="space-y-1.5">
              {suggestions.topRated.map((name) => (
                <li key={name} className="text-sm">
                  {name}
                </li>
              ))}
            </ul>
          </div>
          <div className="flex-1">
            <h3 className="text-xs font-semibold mb-3 text-muted-foreground uppercase tracking-wide">
              Most Collectible
            </h3>
            <ul className="space-y-1.5">
              {suggestions.mostCollectible.map((name) => (
                <li key={name} className="text-sm">
                  {name}
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}

      <Button onClick={onAddGame} size="lg">
        <Plus className="mr-2" />
        Add Your First {platformName} Game
      </Button>
    </div>
  );
}
