# Platform Shortform Management

## Changes Made

The `CategoryDialog` component has been updated to allow viewing and editing platform shortforms (the `id` field of categories).

### Key Features

1. **Visible Shortform Field**: The platform shortform is now displayed as a field in the category management dialog
2. **Editable for New Categories**: When adding a new category, you can specify the shortform
3. **Read-only for Existing Categories**: When editing an existing category, the shortform field is **disabled** to maintain data integrity
4. **Duplicate Prevention**: The system prevents creating categories with duplicate shortforms
5. **Display in List**: The shortform is shown below each category name in the category list

### Backward Compatibility

✅ **Fully backward compatible** - No data conversion or migration needed because:

1. The `id` field already exists in all categories and is already used as the platform identifier in game records
2. We're only exposing this existing field in the UI, not changing its structure
3. When editing existing categories, the shortform is **read-only** (disabled), preventing accidental changes that would break the link between games and their platforms
4. Existing games continue to reference platforms by the same shortform (e.g., 'PS1', 'PS2', 'PC')

### Technical Details

**Updated Fields:**
- The edit form now includes three fields: `id` (shortform), `name`, and `logoUrl`
- The shortform input is disabled during edit mode using `disabled={!!editingId}`
- A tooltip explains why the shortform cannot be changed during editing

**Validation:**
- All three fields are required when adding or editing
- Duplicate shortform detection prevents conflicts
- The system ensures at least one category exists

**UI Layout:**
- Changed from 2-column to 3-column grid for the form
- Added shortform display under category name in the list view

### Usage

**Adding a New Category:**
1. Enter a shortform (e.g., "PS5", "XBOX", "NSW")
2. Enter the full category name (e.g., "PlayStation 5")
3. Enter the logo URL
4. Click "Add Category"

**Editing an Existing Category:**
1. Click the edit button on a category
2. The shortform field will be disabled (grayed out)
3. You can edit the name and logo URL
4. Click "Update Category"

### Why Shortforms Can't Be Changed

The shortform (`id`) is used as a foreign key in all game records. Changing it would break the relationship between games and their platforms. To change a shortform:

1. Export your data
2. Delete the old category
3. Create a new category with the desired shortform
4. Update game records to use the new shortform
5. Re-import the modified data

However, this is not recommended as it's complex and error-prone. Instead, choose shortforms carefully when creating new categories.
