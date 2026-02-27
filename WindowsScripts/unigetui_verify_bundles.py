import json
from pathlib import Path

def load_bundle_ids(filepath):
    """Extracts a set of Package IDs from a .ubundle file."""
    try:
        # Path objects can be read directly
        data = json.loads(filepath.read_text(encoding='utf-8'))
        return {pkg['Id'] for pkg in data.get('packages', [])}
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return set()

# 1. Configuration
# Change 'unigetui_favourite_apps.ubundle' to your master file name
master_bundle_name = "unigetui_favourite_apps.ubundle"
# The folder where your categorized bundles are stored
bundles_folder = Path("./bundles") 

# 2. Setup paths
current_dir = Path(".")
master_file = current_dir / master_bundle_name

if not master_file.exists():
    print(f"Error: Master file '{master_bundle_name}' not found in current directory.")
    exit()

# 3. Recursive search
# rglob("*/*.ubundle") searches all subfolders for .ubundle files
small_bundles = list(bundles_folder.rglob("*.ubundle"))

master_ids = load_bundle_ids(master_file)
migrated_ids = set()

print(f"--- Verification Started ---")
print(f"Master bundle '{master_bundle_name}' contains {len(master_ids)} packages.")
print(f"Searching subfolders in: {bundles_folder.resolve()}")

for bundle_path in small_bundles:
    # Skip the master file if it happens to be inside the bundles folder
    if bundle_path.name == master_bundle_name:
        continue
        
    ids = load_bundle_ids(bundle_path)
    migrated_ids.update(ids)
    # Using .relative_to() makes the output cleaner by showing the subfolder path
    print(f"Checked: {bundle_path.relative_to(bundles_folder)} (Found {len(ids)} apps)")

# 4. Final Comparison
missing_ids = master_ids - migrated_ids

print(f"\n--- Results ---")
if not missing_ids:
    print("SUCCESS: All packages are accounted for in your categorized subfolders!")
else:
    print(f"MISSING: {len(missing_ids)} packages are in the master list but NOT in the subfolders:")
    for mid in sorted(missing_ids):
        print(f" - {mid}")