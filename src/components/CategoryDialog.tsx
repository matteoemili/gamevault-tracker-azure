import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Trash, Plus, Pencil } from '@phosphor-icons/react';
import { toast } from 'sonner';

export interface PlatformCategory {
  id: string;
  name: string;
  logoUrl: string;
}

interface CategoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  categories: PlatformCategory[];
  onSave: (categories: PlatformCategory[]) => void;
}

export function CategoryDialog({ open, onOpenChange, categories, onSave }: CategoryDialogProps) {
  const [localCategories, setLocalCategories] = useState<PlatformCategory[]>(categories);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editForm, setEditForm] = useState({ name: '', logoUrl: '' });

  useEffect(() => {
    setLocalCategories(categories);
  }, [categories]);

  const handleAdd = () => {
    if (!editForm.name.trim() || !editForm.logoUrl.trim()) {
      toast.error('Please fill in all fields');
      return;
    }

    const newCategory: PlatformCategory = {
      id: crypto.randomUUID(),
      name: editForm.name.trim(),
      logoUrl: editForm.logoUrl.trim()
    };

    setLocalCategories(prev => [...prev, newCategory]);
    setEditForm({ name: '', logoUrl: '' });
    toast.success('Category added');
  };

  const handleEdit = (category: PlatformCategory) => {
    setEditingId(category.id);
    setEditForm({ name: category.name, logoUrl: category.logoUrl });
  };

  const handleUpdate = () => {
    if (!editForm.name.trim() || !editForm.logoUrl.trim()) {
      toast.error('Please fill in all fields');
      return;
    }

    setLocalCategories(prev =>
      prev.map(cat =>
        cat.id === editingId
          ? { ...cat, name: editForm.name.trim(), logoUrl: editForm.logoUrl.trim() }
          : cat
      )
    );
    setEditingId(null);
    setEditForm({ name: '', logoUrl: '' });
    toast.success('Category updated');
  };

  const handleDelete = (id: string) => {
    setLocalCategories(prev => prev.filter(cat => cat.id !== id));
    toast.success('Category deleted');
  };

  const handleSave = () => {
    if (localCategories.length === 0) {
      toast.error('You must have at least one category');
      return;
    }
    onSave(localCategories);
    onOpenChange(false);
  };

  const handleCancel = () => {
    setLocalCategories(categories);
    setEditingId(null);
    setEditForm({ name: '', logoUrl: '' });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Manage Categories</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-6">
          <div className="flex flex-col gap-4 border rounded-lg p-4">
            <h3 className="font-semibold text-sm">
              {editingId ? 'Edit Category' : 'Add New Category'}
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="flex flex-col gap-2">
                <Label htmlFor="category-name">Category Name</Label>
                <Input
                  id="category-name"
                  placeholder="e.g., PlayStation 4"
                  value={editForm.name}
                  onChange={(e) => setEditForm(prev => ({ ...prev, name: e.target.value }))}
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="category-logo">Logo URL</Label>
                <Input
                  id="category-logo"
                  placeholder="https://example.com/logo.png"
                  value={editForm.logoUrl}
                  onChange={(e) => setEditForm(prev => ({ ...prev, logoUrl: e.target.value }))}
                />
              </div>
            </div>
            <div className="flex gap-2">
              {editingId ? (
                <>
                  <Button type="button" onClick={handleUpdate} size="sm">
                    Update Category
                  </Button>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => {
                      setEditingId(null);
                      setEditForm({ name: '', logoUrl: '' });
                    }}
                    size="sm"
                  >
                    Cancel Edit
                  </Button>
                </>
              ) : (
                <Button type="button" onClick={handleAdd} size="sm">
                  <Plus className="mr-2" />
                  Add Category
                </Button>
              )}
            </div>
          </div>

          <div className="flex flex-col gap-3">
            <h3 className="font-semibold text-sm">Current Categories ({localCategories.length})</h3>
            <div className="flex flex-col gap-2">
              {localCategories.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">
                  No categories yet. Add one above to get started.
                </p>
              ) : (
                localCategories.map(category => (
                  <div
                    key={category.id}
                    className="flex items-center gap-4 p-3 border rounded-lg hover:bg-muted/50 transition-colors"
                  >
                    <img
                      src={category.logoUrl}
                      alt={category.name}
                      className="h-6 w-auto object-contain"
                      onError={(e) => {
                        (e.target as HTMLImageElement).src = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="24" height="24"%3E%3Crect fill="%23ccc" width="24" height="24"/%3E%3C/svg%3E';
                      }}
                    />
                    <span className="flex-1 font-medium">{category.name}</span>
                    <div className="flex gap-2">
                      <Button
                        size="icon"
                        variant="outline"
                        onClick={() => handleEdit(category)}
                        disabled={editingId !== null}
                      >
                        <Pencil />
                      </Button>
                      <Button
                        size="icon"
                        variant="outline"
                        onClick={() => handleDelete(category.id)}
                        disabled={editingId !== null}
                      >
                        <Trash className="text-destructive" />
                      </Button>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={handleCancel}>
            Cancel
          </Button>
          <Button type="button" onClick={handleSave}>
            Save Changes
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
