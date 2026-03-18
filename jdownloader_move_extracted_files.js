// @ts-nocheck
/*
    Event: Archive extraction finished
    Description: Moves extracted folders (e.g., 435907D5, game.iso) and merges them if they exist.
                 Forces deletion of JSON before writing to bypass "File already exists" error.
*/

var archiveName = archive.getName();

// Case-insensitive check for "addon"
if (archiveName && !archiveName.toLowerCase().includes("addon")) {
    
    var targetBaseFolder = "/mnt/xbox360/god/freshlyExtracted";
    var jsonFilePath = targetBaseFolder + "/contents.json";
    var extractionFolder = archive.getExtractToFolder(); 

    // 1. Prepare Metadata
    var links = archive.getDownloadLinks();
    var firstLink = (links && links.length > 0) ? links[0] : null;
    var url = firstLink ? (firstLink.getUrl() || firstLink.getPluginURL() || "N/A") : "N/A";

    var downloadInfo = {
        timestamp: new Date().toISOString(),
        archiveName: archiveName.toString(),
        url: url.toString(),
        packageName: firstLink ? firstLink.getPackage().getName().toString() : "N/A",
        movedItems: []
    };

    // 2. Identify top-level extracted items
    var extractedPaths = archive.getExtractedFiles(); 
    var itemsToMove = {};

    if (extractedPaths && extractedPaths.length > 0) {
        for (var i = 0; i < extractedPaths.length; i++) {
            var current = getPath(extractedPaths[i]);
            var rootItem = null;

            while (current != null && current.getParent() != null) {
                if (current.getParent().getAbsolutePath().toString() === getPath(extractionFolder).getAbsolutePath().toString()) {
                    rootItem = current;
                    break;
                }
                current = current.getParent();
            }

            if (rootItem != null) {
                itemsToMove[rootItem.getAbsolutePath().toString()] = rootItem;
            }
        }

        // 3. Move/Merge the items
        for (var pathKey in itemsToMove) {
            var item = itemsToMove[pathKey];
            var itemName = item.getName().toString();
            var destinationPath = targetBaseFolder + "/" + itemName;
            var destObj = getPath(destinationPath);

            if (item.exists()) {
                if (destObj.exists() && destObj.isDirectory() && item.isDirectory()) {
                    // Merge contents into existing folder
                    var subItems = item.getChildren();
                    for (var s = 0; s < subItems.length; s++) {
                        subItems[s].moveTo(destinationPath + "/" + subItems[s].getName());
                    }
                    downloadInfo.movedItems.push(itemName);
                } else {
                    // Normal move
                    if (item.moveTo(destinationPath)) {
                        downloadInfo.movedItems.push(itemName);
                    }
                }
            }
        }

        // 4. Safe JSON Update (Delete before Write)
        if (downloadInfo.movedItems.length > 0) {
            var currentJsonContent = [];
            var jsonFile = getPath(jsonFilePath);
            
            if (jsonFile.exists()) {
                try {
                    var rawData = readFile(jsonFilePath);
                    if (rawData && rawData.trim().length > 0) {
                        currentJsonContent = JSON.parse(rawData);
                    }
                } catch (e) {
                    currentJsonContent = [];
                }
                
                // Remove duplicates in memory
                for (var j = currentJsonContent.length - 1; j >= 0; j--) {
                    if (currentJsonContent[j].archiveName === downloadInfo.archiveName) {
                        currentJsonContent.splice(j, 1);
                    }
                }
            }

            currentJsonContent.push(downloadInfo);

            // CRITICAL FIX: Delete the file from the filesystem before writing the new version
            if (jsonFile.exists()) {
                jsonFile.delete();
            }
            
            // Now write the new content
            writeFile(jsonFilePath, JSON.stringify(currentJsonContent, null, 4), false);
        }
        
        // 5. Cleanup extraction container if empty
        var folderObj = getPath(extractionFolder);
        if (folderObj.exists() && folderObj.isDirectory() && folderObj.getChildren().length === 0) {
            folderObj.delete();
        }
    }
}
