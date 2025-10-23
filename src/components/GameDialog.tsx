import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Game, Platform, PLATFORM_NAMES } from '@/lib/types';
import { Calendar as CalendarIcon } from '@phosphor-icons/react';
import { format } from 'date-fns';

interface GameDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (game: Game) => void;
  game?: Game;
}

export function GameDialog({ open, onOpenChange, onSave, game }: GameDialogProps) {
  const [formData, setFormData] = useState<Partial<Game>>(
    game || {
      name: '',
      platform: 'PS1',
      acquired: false,
      priority: false
    }
  );

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!formData.name?.trim() || !formData.platform) return;

    const gameData: Game = {
      id: game?.id || crypto.randomUUID(),
      name: formData.name.trim(),
      platform: formData.platform as Platform,
      acquired: formData.acquired || false,
      targetPrice: formData.targetPrice,
      priority: formData.priority,
      purchasePrice: formData.purchasePrice,
      acquisitionDate: formData.acquisitionDate,
      seller: formData.seller,
      notes: formData.notes
    };

    onSave(gameData);
    onOpenChange(false);
    
    if (!game) {
      setFormData({
        name: '',
        platform: 'PS1',
        acquired: false,
        priority: false
      });
    }
  };

  const handleDateSelect = (date: Date | undefined) => {
    setFormData(prev => ({
      ...prev,
      acquisitionDate: date ? format(date, 'yyyy-MM-dd') : undefined
    }));
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{game ? 'Edit Game' : 'Add Game'}</DialogTitle>
        </DialogHeader>
        
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor="name">Game Name *</Label>
            <Input
              id="name"
              value={formData.name || ''}
              onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
              required
            />
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="platform">Platform *</Label>
            <Select
              value={formData.platform}
              onValueChange={(value) => setFormData(prev => ({ ...prev, platform: value as Platform }))}
            >
              <SelectTrigger id="platform">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(PLATFORM_NAMES).map(([key, name]) => (
                  <SelectItem key={key} value={key}>
                    {name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex items-center gap-2">
            <Switch
              id="acquired"
              checked={formData.acquired || false}
              onCheckedChange={(checked) => setFormData(prev => ({ ...prev, acquired: checked }))}
            />
            <Label htmlFor="acquired">Acquired</Label>
          </div>

          {!formData.acquired && (
            <>
              <div className="flex flex-col gap-2">
                <Label htmlFor="targetPrice">Target Price</Label>
                <Input
                  id="targetPrice"
                  type="number"
                  step="0.01"
                  min="0"
                  value={formData.targetPrice || ''}
                  onChange={(e) => setFormData(prev => ({ 
                    ...prev, 
                    targetPrice: e.target.value ? parseFloat(e.target.value) : undefined 
                  }))}
                />
              </div>

              <div className="flex items-center gap-2">
                <Switch
                  id="priority"
                  checked={formData.priority || false}
                  onCheckedChange={(checked) => setFormData(prev => ({ ...prev, priority: checked }))}
                />
                <Label htmlFor="priority">Priority Purchase</Label>
              </div>
            </>
          )}

          {formData.acquired && (
            <>
              <div className="flex flex-col gap-2">
                <Label htmlFor="purchasePrice">Purchase Price</Label>
                <Input
                  id="purchasePrice"
                  type="number"
                  step="0.01"
                  min="0"
                  value={formData.purchasePrice || ''}
                  onChange={(e) => setFormData(prev => ({ 
                    ...prev, 
                    purchasePrice: e.target.value ? parseFloat(e.target.value) : undefined 
                  }))}
                  placeholder="Leave empty for pre-owned/gifted"
                />
              </div>

              <div className="flex flex-col gap-2">
                <Label htmlFor="acquisitionDate">Acquisition Date</Label>
                <Popover>
                  <PopoverTrigger asChild>
                    <Button
                      id="acquisitionDate"
                      variant="outline"
                      className="justify-start text-left font-normal"
                    >
                      <CalendarIcon className="mr-2" />
                      {formData.acquisitionDate ? format(new Date(formData.acquisitionDate), 'PPP') : 'Pick a date'}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0">
                    <Calendar
                      mode="single"
                      selected={formData.acquisitionDate ? new Date(formData.acquisitionDate) : undefined}
                      onSelect={handleDateSelect}
                      initialFocus
                    />
                  </PopoverContent>
                </Popover>
              </div>

              <div className="flex flex-col gap-2">
                <Label htmlFor="seller">Seller</Label>
                <Input
                  id="seller"
                  value={formData.seller || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, seller: e.target.value }))}
                />
              </div>
            </>
          )}

          <div className="flex flex-col gap-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea
              id="notes"
              value={formData.notes || ''}
              onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
              rows={3}
            />
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit">{game ? 'Save Changes' : 'Add Game'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
