# Video Game Collection Tracker

A comprehensive collection management application for tracking PlayStation and PC video games across multiple platforms with full import/export capabilities.

**Experience Qualities**:
1. **Organized** - Clean, structured interface that makes finding and managing games effortless with clear visual hierarchy
2. **Efficient** - Quick data entry with smart forms and bulk import/export features for managing large collections
3. **Informative** - At-a-glance status indicators showing owned vs. wanted games with priority flags

**Complexity Level**: Light Application (multiple features with basic state)
The app manages persistent game collection data with CRUD operations, filtering, search, and CSV import/export functionality, but doesn't require user accounts or complex backend integrations.

## Essential Features

### Game Entry Management
- **Functionality**: Add, edit, and delete game entries with platform-specific information
- **Purpose**: Core collection tracking with acquisition details and wishlist management
- **Trigger**: Click "Add Game" button or edit icon on existing entry
- **Progression**: Open dialog → Select platform → Enter game details (name, prices, dates, notes) → Save → Entry appears in collection list
- **Success criteria**: Games persist between sessions, all fields validate correctly, acquired/wanted states display properly

### Platform Filtering
- **Functionality**: Filter collection by console (PS1, PS2, PS3, PSP, PC) or view all
- **Purpose**: Quick navigation through platform-specific subsets of the collection
- **Trigger**: Click platform filter buttons or "All" option
- **Progression**: Click platform button → List updates instantly → Console logo indicates filtered view
- **Success criteria**: Filtering is instant, counts update accurately, multiple filters can combine with status filters

### Status Filtering & Search
- **Functionality**: Filter by owned/wanted/priority status and search by game name
- **Purpose**: Find specific games or view collection subsets (wishlist, priority purchases, owned games)
- **Trigger**: Select filter dropdown or type in search field
- **Progression**: Select status filter / type search text → Results update in real-time → Matching games display
- **Success criteria**: Search is case-insensitive, filters combine logically, empty states show helpful messages

### CSV Import/Export
- **Functionality**: Bulk import collection data, export entire collection, download blank template
- **Purpose**: Migrate existing collections, backup data, share lists, batch data entry
- **Trigger**: Click menu button → Select import/export option
- **Progression**: Template Download: Click → CSV downloads | Import: Click → Choose file → Parse CSV → Validate → Merge with collection → Success message | Export: Click → Current collection downloads as CSV
- **Success criteria**: CSV format matches template exactly, import validates all fields, export includes all current data, errors display helpful messages

### Visual Platform Identification
- **Functionality**: Display official platform logos next to each game title
- **Purpose**: Instant visual recognition of game platform without reading text
- **Trigger**: Automatic when game entry displays
- **Progression**: Game loads → Logo fetches from URL → Displays alongside title
- **Success criteria**: All five platform logos render correctly, consistent sizing, graceful fallback if image fails

## Edge Case Handling

- **Empty Collection**: Display welcoming empty state with quick-start guide and "Add Game" CTA
- **Import Errors**: Show detailed validation errors (missing fields, invalid dates, unknown platforms) with line numbers
- **Duplicate Entries**: Allow duplicates (same game, different purchases) but warn user during import
- **Missing Prices**: Display "Pre-owned/gifted/other" text when purchase price is 0 or empty for acquired games
- **Search No Results**: Show "No games found" message with active filters displayed and clear filters option
- **Large Collections**: Implement virtual scrolling or pagination if collection exceeds 100 games
- **CSV Edge Cases**: Handle quoted fields with commas, various date formats (MM/DD/YYYY, YYYY-MM-DD), empty optional fields

## Design Direction

The design should feel organized and professional like a personal database or inventory system, with clean data tables and efficient forms. Minimal interface that prioritizes information density and quick scanning, with platform logos adding visual interest. The aesthetic should be clean and modern with a slight gaming aesthetic through the console branding colors without being playful or childish.

## Color Selection

**Triadic color scheme** - Using PlayStation blue as anchor with complementary warm accents for priority/status indicators, creating visual hierarchy while maintaining professional appearance.

- **Primary Color**: PlayStation Blue (oklch(0.45 0.15 250)) - Represents the dominant PlayStation platforms, communicates trust and organization
- **Secondary Colors**: Neutral Gray (oklch(0.95 0 0)) for cards/backgrounds, Dark Gray (oklch(0.25 0 0)) for secondary actions
- **Accent Color**: Orange (oklch(0.65 0.18 50)) - Warm accent for priority flags, wanted status, and important CTAs
- **Foreground/Background Pairings**:
  - Background (White oklch(1 0 0)): Dark text oklch(0.2 0 0) - Ratio 16.3:1 ✓
  - Card (Light Gray oklch(0.98 0 0)): Dark text oklch(0.2 0 0) - Ratio 15.8:1 ✓
  - Primary (PS Blue oklch(0.45 0.15 250)): White text oklch(1 0 0) - Ratio 6.2:1 ✓
  - Secondary (Gray oklch(0.95 0 0)): Dark text oklch(0.25 0 0) - Ratio 12.1:1 ✓
  - Accent (Orange oklch(0.65 0.18 50)): White text oklch(1 0 0) - Ratio 4.8:1 ✓
  - Muted (Medium Gray oklch(0.93 0 0)): Muted text oklch(0.5 0 0) - Ratio 7.2:1 ✓

## Font Selection

Clean, technical fonts that suggest organization and data management, with excellent readability for scanning lists and tables.

- **Typographic Hierarchy**:
  - H1 (App Title): Inter Bold / 32px / -0.02em letter spacing - Strong presence for branding
  - H2 (Section Headers): Inter Semibold / 20px / -0.01em - Clear section delineation
  - H3 (Game Titles): Inter Medium / 16px / normal - Emphasis within cards
  - Body (Details/Labels): Inter Regular / 14px / normal / 1.5 line height - Primary readable text
  - Small (Metadata): Inter Regular / 13px / normal / 1.4 line height - Dates, prices, counts
  - Buttons: Inter Medium / 14px / normal - Clear call-to-action text

## Animations

Subtle, efficient animations that guide attention and confirm actions without slowing down data entry workflows - focusing on state transitions and feedback rather than decorative motion.

- **Purposeful Meaning**: Quick fade-ins for dialogs (200ms) suggest content appearing, slide-ups for toasts (250ms) feel like system notifications, gentle scale on hover (150ms) indicates interactivity
- **Hierarchy of Movement**: Priority to user actions (button press feedback, form submission), then data changes (filter results, new entries), minimal motion on static content (logos, text)

## Component Selection

- **Components**: 
  - Dialog: Game entry form (add/edit)
  - Card: Individual game entries in collection grid
  - Table: Optional tabular view for detailed collection browsing
  - Button: Actions (Add, Edit, Delete, Import, Export, Filters)
  - Input: Search field, form text fields
  - Select: Platform dropdown in forms
  - Switch: Priority toggle, Acquired/Wanted toggle
  - Badge: Platform tags, status indicators (Owned, Wanted, Priority)
  - DropdownMenu: Main menu for import/export actions
  - Calendar: Date picker for acquisition date
  - Textarea: Notes field
  - Alert: Import/export confirmations and errors
  - Separator: Visual grouping in forms

- **Customizations**: 
  - Platform logo component (custom image wrapper with consistent sizing)
  - CSV parser/generator utility
  - Game card with conditional field rendering (show target price OR purchase price based on status)
  - Filter bar component combining search, platform filters, and status filters

- **States**: 
  - Buttons: Blue primary for main actions, subtle gray for secondary, red for delete (all with hover lift and active press)
  - Cards: Subtle shadow at rest, elevated shadow on hover, border highlight when filtered
  - Inputs: Light gray border default, blue border on focus, red border on validation error
  - Badges: Filled colored backgrounds for statuses (blue=owned, orange=wanted/priority)

- **Icon Selection**: 
  - Plus (Add game)
  - Pencil (Edit entry)
  - Trash (Delete game)
  - FunnelSimple (Filter toggle)
  - MagnifyingGlass (Search)
  - DownloadSimple (Export/Download template)
  - UploadSimple (Import)
  - DotsThree (More menu)
  - Star/StarFilled (Priority indicator)
  - Check (Owned/acquired indicator)
  - Calendar (Date picker)

- **Spacing**: 
  - Card padding: p-6
  - Form fields gap: gap-4
  - Section margins: mb-8
  - Grid gaps: gap-4 (mobile), gap-6 (desktop)
  - Button padding: px-4 py-2
  - Consistent 8px baseline grid (multiples of 2/4/6/8)

- **Mobile**: 
  - Stack game cards vertically with full width
  - Filter bar becomes collapsible accordion
  - Dialog forms adjust to mobile viewport with stacked fields
  - Platform logos scale down proportionally
  - Table view switches to card view on mobile
  - Touch-friendly hit areas (min 44px) for all interactive elements
  - Bottom action buttons stay accessible with sticky positioning
