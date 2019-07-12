script "Wix Packager"
local sUsedComponentIds, sUsedDirectoryIds, sUsedShortNames
local sScriptsToCompile
local sInstallerName

command processCopyFilesFile pBuildProfile, @xFiledata, pOutputFolder, pOutputFilename, pFileSettingsA
  local tError, tConfigA, tTreeId, tFolders, tFiles, tComponentNode, tFileNode
  local tTargetDirNode, tInstallDirNode, tFileId

  _replaceVariables xFiledata, pBuildProfile

  if pOutputFilename ends with ".wxs" then
    put pOutputFilename into line (the number of lines of sScriptsToCompile + 1) of sScriptsToCompile
  end if

  if tError is empty then
    put revXMLCreateTree(xFiledata, true, true, false) into tTreeId
    if tTreeId begins with "xmlerr," then
      put "Error parsing XML:" && item 2 to -1 of tTreeId into tError
    end if
  end if

  # Find TARGETDIR node
  if tError is empty then
    put revXMLMatchingNode(tTreeId, "/Wix/Product", "Directory", "Id", "TARGETDIR", -1) into tTargetDirNode
    if tTargetDirNode begins with "xmlerr," then
      if tTargetDirNode contains "can't find element" then
        # This file isn't the main Product xml file (UI maybe)
        put "cancel" into tError
      else
        put "Error finding TARGETDIR node:" && item 2 to -1 of tTargetDirNode into tError
      end if
    end if
  end if

  # Find INSTALLDIR node
  if tError is empty then
    put revXMLMatchingNode(tTreeId, "/Wix/Product", "Directory", "Id", "INSTALLDIR", -1) into tInstallDirNode
    if tInstallDirNode begins with "xmlerr," then
      put "Error finding INSTALLDIR node:" && item 2 to -1 of tInstallDirNode into tError
    end if
  end if

  if tError is empty then
    _addURLProtocols tTreeId, tTargetDirNode
    put the result into tError
  end if


  # Add files
  if tError is empty then
    put _foldersInFolder(pOutputFolder & "/windows") into tFolders
    put _filesInFolder(pOutputFolder & "/windows") into tFiles

    repeat for each line tFilename in tFiles
      _addFileToTree tTreeId, tInstallDirNode, pOutputFolder, pOutputFolder & "/windows", tFilename
      put the result into tError

      if tError is not empty then
        exit repeat
      end if
    end repeat
  end if

  # Add folders
  if tError is empty then
    repeat for each line tFilename in tFolders
      _addDirectoryToTree tTreeId, tInstallDirNode, pOutputFolder, pOutputFolder & "/windows", tFilename
      put the result into tError

      if tError is not empty then
        exit repeat
      end if
    end repeat
  end if

  # Add componentref's
  if tError is empty then
    _addComponentIdsToFeatureNode tTreeId
    put the result into tError
  end if

  if tError is empty then
    put textEncode(revXMLText(tTreeId, empty, true), "utf8") into xFiledata
  end if


  if tTreeId is an integer then
    revXMLDeleteTree tTreeId
  end if

  put empty into sUsedComponentIds
  put empty into sUsedDirectoryIds
  put empty into sUsedShortNames

  if tError is not empty and tError is not "cancel" then
    answer error tError
  end if
end processCopyFilesFile


private command _addComponentIdsToFeatureNode pTreeId
  local tError

  if tError is empty then
    local tFeatureNode

    put revXMLMatchingNode(pTreeId, "/Wix/Product", "Feature", "Id", "Complete", -1) into tFeatureNode
    if tFeatureNode begins with "xmlerr," then
      put "Error finding Feature node:" && item 2 to -1 of tFeatureNode into tError
    end if
  end if

  if tError is empty then
    local tComponentRefNode, tId

    sort lines of sUsedComponentIds ascending

    repeat for each line tId in sUsedComponentIds
      revXMLAddNode pTreeId, tFeatureNode, "ComponentRef", empty
      put the result into tComponentRefNode
      if tComponentRefNode begins with "xmlerr," then
        put "Unable to add componentref node:" && item 2 to -1 of tComponentRefNode into tError
        exit repeat
      end if

      revXMLSetAttribute pTreeId, tComponentRefNode, "Id", tId
    end repeat
  end if

  return tError for error
end _addComponentIdsToFeatureNode


private command _addDirectoryToTree pTreeId, pParentNode, pRootFolder, pParentPath, pFolder
  local tError, tDirectoryNode, tFolderId, tFiles, tFolders, tFolder

  revXMLAddNode pTreeId, pParentNode, "Directory", empty
  put the result into tDirectoryNode
  if tDirectoryNode begins with "xmlerr," then
    return "Unable to add directory node:" && item 2 to -1 of tDirectoryNode for error
  end if

  put _uniqueDirectoryId(pFolder) into tFolderId

  revXMLSetAttribute pTreeId, tDirectoryNode, "Id", tFolderId
  revXMLSetAttribute pTreeId, tDirectoryNode, "Name", pFolder

  put _filesInFolder(pParentPath & "/" & pFolder) into tFiles

  repeat for each line tFilename in tFiles
    _addFileToTree pTreeId, tDirectoryNode, pRootFolder, pParentPath & "/" & pFolder, tFilename
  end repeat

  put _foldersInFolder(pParentPath & "/" & pFolder) into tFolders

  repeat for each line tFolder in tFolders
    _addDirectoryToTree pTreeId, tDirectoryNode, pRootFolder, pParentPath & "/" & pFolder, tFolder
  end repeat

  return tError
end _addDirectoryToTree


private command _addFileToTree pTreeId, pParentNode, pRootFolder, pParentFolder, pFilename
  local tComponentNode, tFileNode, tFileId, tSourceFile

  revXMLAddNode pTreeId, pParentNode, "Component", empty
  put the result into tComponentNode
  if tComponentNode begins with "xmlerr," then
    return "Unable to add component to directory node:" && item 2 to -1 of tComponentNode for error
  end if

  revXMLAddNode pTreeId, tComponentNode, "File", empty
  put the result into tFileNode
  if tFileNode begins with "xmlerr," then
    return "Unable to add file to component node:" && item 2 to -1 of tFileNode for error
  end if

  put _uniqueComponentId(pFilename) into tFileId
  put _makeRelativePath(pParentFolder & "/" & pFilename, pRootFolder) into tSourceFile
  replace slash with backslash in tSourceFile

  revXMLSetAttribute pTreeId, tComponentNode, "Id", tFileId
  revXMLSetAttribute pTreeId, tComponentNode, "Guid", "{" & uuid() & "}"

  revXMLSetAttribute pTreeId, tFileNode, "Id", tFileId
  revXMLSetAttribute pTreeId, tFileNode, "Name", pFilename
  revXMLSetAttribute pTreeId, tFileNode, "KeyPath", "yes"
  revXMLSetAttribute pTreeId, tFileNode, "ShortName", _uniqueShortName( _fileExtractExtension(pFilename) )
  revXMLSetAttribute pTreeId, tFileNode, "DiskId", "1"
  revXMLSetAttribute pTreeId, tFileNode, "Source", tSourceFile

  # Add shortcuts to desktop and start menu for executable
  if pFilename is levureAppGet("name") & ".exe" then
    local tNode

    revXMLAddNode pTreeId, tComponentNode, "RemoveFolder", empty
    put the result into tNode

    revXMLSetAttribute pTreeId, tNode, "Directory", "StartMenuAppFolder"
    revXMLSetAttribute pTreeId, tNode, "Id", "removeStartMenuAppFolder"
    revXMLSetAttribute pTreeId, tNode, "On", "uninstall"

    revXMLAddNode pTreeId, tComponentNode, "Shortcut", empty
    put the result into tNode

    revXMLSetAttribute pTreeId, tNode, "Advertise", "yes"
    revXMLSetAttribute pTreeId, tNode, "Directory", "DesktopFolder"
    revXMLSetAttribute pTreeId, tNode, "Id", "shortcut_0001"
    revXMLSetAttribute pTreeId, tNode, "Name", levureAppGet("name")
    revXMLSetAttribute pTreeId, tNode, "Icon", "application.ico"
    revXMLSetAttribute pTreeId, tNode, "ShortName", _uniqueShortName()
    revXMLSetAttribute pTreeId, tNode, "Show", "normal"

    revXMLAddNode pTreeId, tComponentNode, "Shortcut", empty
    put the result into tNode

    revXMLSetAttribute pTreeId, tNode, "Advertise", "yes"
    revXMLSetAttribute pTreeId, tNode, "Directory", "StartMenuAppFolder"
    revXMLSetAttribute pTreeId, tNode, "Id", "shortcut_0002"
    revXMLSetAttribute pTreeId, tNode, "Name", levureAppGet("name")
    revXMLSetAttribute pTreeId, tNode, "Icon", "application.ico"
    revXMLSetAttribute pTreeId, tNode, "ShortName", _uniqueShortName()
    revXMLSetAttribute pTreeId, tNode, "Show", "normal"
  end if

  return empty
end _addFileToTree


private command _addURLProtocols pTreeId, pParentNode
  local tListA, tProtocol
  local tComponentNode, tRegistryNode, tRegKeyId

  put levureAppGet("url protocols") into tListA
  repeat for each key tProtocol in tListA
    if word 1 to -1 of line 1 of tProtocol is not empty and word 1 to -1 of line 1 of tListA[tProtocol] is not empty then

      _addProtocol pTreeId, pParentNode, tProtocol, tProtocol, empty, "URL:" & tListA[tProtocol]
      if the result is not empty then return the result

      _addProtocol pTreeId, pParentNode, tProtocol, tProtocol, "URL Protocol", ""
      if the result is not empty then return the result

      _addProtocol pTreeId, pParentNode, tProtocol, \
            tProtocol & "\DefaultIcon", \
            empty, \
            "[INSTALLDIR]" & sInstallerName & ".exe,1"
      if the result is not empty then return the result

      _addProtocol pTreeId, pParentNode, tProtocol, \
            tProtocol & "\shell\open\command", \
            empty, \
            "\&quot;[INSTALLDIR]" & sInstallerName & ".exe\&quot; -url \&quot;%1\"
      if the result is not empty then return the result
    end if
  end repeat

  return empty
end _addURLProtocols


private command _addProtocol pTreeId, pParentNode, pProtocol, pKey, pName, pValue
  local tComponentNode, tRegistryNode, tRegKeyId

  revXMLAddNode pTreeId, pParentNode, "Component", empty
  put the result into tComponentNode
  if tComponentNode begins with "xmlerr," then
    return "Unable to add component to directory node:" && item 2 to -1 of tComponentNode for error
  end if

  revXMLAddNode pTreeId, tComponentNode, "RegistryValue", empty
  put the result into tRegistryNode
  if tRegistryNode begins with "xmlerr," then
    return "Unable to add registry value to component node:" && item 2 to -1 of tRegistryNode for error
  end if

  put _uniqueComponentId("RegURLProtocol" && pProtocol) into tRegKeyId

  revXMLSetAttribute pTreeId, tComponentNode, "Id", tRegKeyId
  revXMLSetAttribute pTreeId, tComponentNode, "Guid", "{" & uuid() & "}"

  revXMLSetAttribute pTreeId, tRegistryNode, "Id", tRegKeyId
  revXMLSetAttribute pTreeId, tRegistryNode, "Key", pKey
  revXMLSetAttribute pTreeId, tRegistryNode, "KeyPath", "yes"
  if pName is not empty then
    revXMLSetAttribute pTreeId, tRegistryNode, "Name", pName
  end if
  revXMLSetAttribute pTreeId, tRegistryNode, "Root", "HKCR"
  revXMLSetAttribute pTreeId, tRegistryNode, "Type", "string"
  revXMLSetAttribute pTreeId, tRegistryNode, "Value", pValue

  return empty
end _addProtocol


command packagingComplete pBuildProfile, pOutputFolder, pAppA
  local tCert, tScript, tCandleCmd, tLightCmd, tDelCmd, tBatch, tOutputFilename

  put pAppA["windows signing certificate"] into tCert

  put "candle" into tCandleCmd
  put "light" into tLightCmd
  put "del" into tDelCmd

  set the itemDelimiter to "."
  repeat for each line tScript in sScriptsToCompile
    put space & quote & tScript & quote after tCandleCmd
    put space & quote & item 1 to -2 of tScript & ".wixobj" & quote after tLightCmd
    put space & quote & item 1 to -2 of tScript & ".wixobj" & quote after tDelCmd
  end repeat

  put " -o " & quote & sInstallerName & ".msi" & quote after tLightCmd
  put " " & quote & sInstallerName & ".wixpdb" & quote & " /q" after tDelCmd

  local tSignTool
  put "signtool.exe" into tSignTool

  put "@ECHO OFF" & cr into tBatch
  put "TITLE Compile Wix files" & cr after tBatch

  if tCert is not empty then
    put "set /p password=" & quote & "Enter signing certificate password: " & quote & cr after tBatch
    put tSignTool && "sign /f" && quote & tCert & quote  && "/p %password%" && \
          "/t http://timestamp.comodoca.com/authenticodel" && quote & ".\windows\" & levureAppGet("name") & ".exe" & quote & cr after tBatch
  end if

  put tCandleCmd & cr after tBatch
  put tLightCmd & cr after tBatch
  put tDelCmd & cr after tBatch

  if tCert is not empty then
    put tSignTool && "sign /f" && quote & tCert & quote  && "/p %password%" && \
          "/t http://timestamp.comodoca.com/authenticodel" && quote & sInstallerName & ".msi" & quote & cr after tBatch
  end if
  put "PAUSE" after tBatch

  put pOutputFolder & "/Wix Compiler.bat" into tOutputFilename

  put textEncode(tBatch, "utf8") into url ("binfile:" & tOutputFilename)

  if the platform is "win32" then
    local tDefaultFolder

    put the defaultFolder into tDefaultFolder
    set the defaultFolder to pOutputFolder
    launch document tOutputFilename
  end if

  put empty into sScriptsToCompile
  put empty into sInstallerName
end packagingComplete


private function _filesInFolder pFolder
  local tFiles

  put files(pFolder) into tFiles
  filter tFiles without ".*"
  return tFiles
end _filesInFolder


private function _foldersInFolder pFolder
  local tFolders

  put folders(pFolder) into tFolders
  filter tFolders without ".*"
  filter tFolders without "..*"
  return tFolders
end _foldersInFolder


/**
Summary: Creates a valid id for a component.

Description:
Identifiers may contain ASCII characters A-Z, a-z, digits, underscores (_), or periods (.).
Every identifier must begin with either a letter or an underscore.

Returns: nothing
*/
private function _uniqueComponentId pFilename, pAdd
  local tFileId

  put _convertToValidId(pFilename) into pFilename
  put _fileUniqueFileNameForList(pFilename, sUsedComponentIds, "_", 255) into tFileId
  put tFileId & cr after sUsedComponentIds

  return tFileId
end _uniqueComponentId


private function _uniqueDirectoryId pFolder, pAdd
  local tFolderId

  put _convertToValidId(pFolder) into pFolder
  put _fileUniqueFileNameForList(pFolder, sUsedDirectoryIds, "_", 255) into tFolderId
  put tFolderId & cr after sUsedDirectoryIds

  return tFolderId
end _uniqueDirectoryId


private function _uniqueShortName pExtension
  local tShortName

  if pExtension is not empty then
    put "." & char 1 to 3 of pExtension into pExtension
  end if

  repeat forever
    put char 1 to 8 of uuid() & pExtension into tShortName
    if tShortName is not among the keys of sUsedShortNames then
      put empty into sUsedShortNames[tShortName]
      exit repeat
    end if
  end repeat

  return tShortName
end _uniqueShortName


private command _replaceVariables @xFileData, pBuildProfile
  local tWixA, tVersion, tConfigA

  put levureAppGet("wix") into tWixA

  put levureAppGet("version") into tVersion
  set the itemDelimiter to "."

  replace textEncode("[[NAME]]", "utf8") with levureAppGet("name") in xFileData
  replace textEncode("[[VERSION]]", "utf8") with tVersion in xFileData
  replace textEncode("[[MAJOR_VERSION]]", "utf8") with item 1 of tVersion in xFileData
  replace textEncode("[[APP_VERSION]]", "utf8") with item 1 to 2 of tVersion in xFileData
  replace textEncode("[[BUILD]]", "utf8") with levureAppGet("build") in xFileData
  replace textEncode("[[BUILD_PROFILE]]", "utf8") with tolower(pBuildProfile) in xFileData
  replace textEncode("[[PRODUCT_ID]]", "utf8") with uuid() in xFileData
  replace textEncode("[[PRODUCT_UPGRADECODE]]", "utf8") with tWixA["upgrade code"] in xFiledata

  put levureAppGet("build profiles") into tConfigA

  put tConfigA[pBuildProfile]["installer name"]["windows"] into sInstallerName
  if sInstallerName is empty then
    put tConfigA["all profiles"]["installer name"]["windows"] into sInstallerName
  end if
  if sInstallerName is empty then
    put tConfigA[pBuildProfile]["installer name"]["all platforms"] into sInstallerName
  end if
  if sInstallerName is empty then
    put tConfigA["all profiles"]["installer name"]["all platforms"] into sInstallerName
  end if

  replace textEncode("[[INSTALLER_NAME]]", "utf8") with sInstallerName in xFileData
end _replaceVariables


/**
Summary: Creates a unique name for a list of files.

Parameters:
pFileName: The name of the file to make unique.
pFileList: List of file names to compare against.
pDelimiter: Delimiter to use in name.
pMaxLength: Maximum length for the resulting filename.

Returns: Unique name
*/
function _fileUniqueFileNameForList pFileName, pFileList, pDelimiter, pMaxLength
  local tName, tBaseName, tExtension
  local tEffectiveBaseName, tCounter

  put _fileExtractName(pFileName) into tName
  put _fileExtractBaseName(pFileName) into tBaseName
  put _fileExtractExtension(pFileName) into tExtension

  if pDelimiter is empty then put space into pDelimiter

  if pMaxLength is an integer and tExtension is not empty then
    subtract 1 from pMaxLength -- "."
    subtract length(tExtension) from pMaxLength
  end if

  if pMaxLength > 0 then
    ## Remember, we are discounting .ext in pMaxLength
    put char 1 to pMaxLength of tBaseName into tName
    if tExtension is not empty then put "." & tExtension after tName
  end if

  set the wholeMatches to true
  repeat while lineOffset(tName, pFileList) > 0
    add 1 to tCounter

    if pMaxLength > 0 then
      put char 1 to (pMaxLength - length(tCounter) - 1) of tBaseName into tEffectiveBaseName
    else
      put tBaseName into tEffectiveBaseName
    end if

    # Don't double-up the delimiter
    if the last char of tEffectiveBaseName is not pDelimiter then
      put tEffectiveBaseName & pDelimiter & tCounter into tName
    else
      put tEffectiveBaseName & tCounter into tName
    end if

    if tExtension is not empty then
      put "." & tExtension after tName
    end if
  end repeat

  return tName
end _fileUniqueFileNameForList


function _fileExtractName pFilePath
  set the itemDelimiter to slash
  return the last item of pFilePath
end _fileExtractName


-- base name but no extension
function _fileExtractBaseName pFilePath
  local theName

  set the itemDelimiter to slash
  put the last item of pFilePath into theName
  set the itemDelimiter to "."
  if the number of items of theName > 1 then
    return item 1 to -2 of theName
  else
    return theName
  end if
end _fileExtractBaseName


function _fileExtractExtension pFilePath
  local tName

  set the itemDelimiter to slash
  put the last item of pFilePath into tName
  set the itemDelimiter to "."
  if the number of items of tName > 1 then
    return the last item of tName
  else
    return empty
  end if
end _fileExtractExtension


private function _makeRelativePath pFilename, pRootFolder
  local tIndex
  local tMatchCount = 0
  local tNonMatchCount =0

  ## NORMALIZE
  if char 1 of pFilename is slash then delete char 1 of pFilename
  if char 1 of pRootFolder is slash then delete char 1 of pRootFolder
  if the last char of pFilename is slash then delete the last char of pFilename
  if the last char of pRootFolder is slash then delete the last char of pRootFolder
  set the itemDelimiter to slash

  if pFilename is empty then return empty
  if pRootFolder is empty then return empty

  ## IS pFilename A CHILD DIRECTORY OF pRootFolder?
  if pRootFolder is item 1 to (the number of items of pRootFolder) of pFilename then
    delete char 1 to length(pRootFolder) + 1 of pFilename
    put "./" before pFilename
  else if pFilename is char 1 to length(pFilename) of pRootFolder then
    delete char 1 to length(pFilename) + 1 of pRootFolder
    put empty into pFilename
    repeat with tIndex = 1 to the number of items of pRootFolder
      put "../" after pFilename
    end repeat
  else
    ## DETERMINE WHERE PATHS DIVERGE
    repeat with tIndex = 1 to the number of items of pFilename
      if item tIndex of pFilename is not item tIndex of pRootFolder then
        put tIndex - 1 into tMatchCount
        put the number of items of pRootFolder - tIndex + 1 into tNonMatchCount
        exit repeat
      end if
    end repeat

    if tMatchCount > 0 then
      delete item 1 to tMatchCount of pFilename
    end if

    repeat with tIndex = 1 to tNonMatchCount
      put "../" before pFilename
    end repeat
  end if

  return pFilename
end _makeRelativePath


function _convertToValidId pString
  local tSeperator, tChar, tCode, tNewString

  put "_" into tSeperator
  put _convertHighToLowISO(pString) into pString

  repeat for each char tChar in pString
    put nativeCharToNum(tChar) into tCode
    if (tCode >= 48 and tCode <= 57) or \
          (tCode >= 65 and tCode <= 90) or \
          (tCode >= 97 and tCode <= 122) or \
          tCode is 95 or tCode is 46 then
      put tChar after tNewString
    else
      put tSeperator after tNewString
    end if
  end repeat

  return tNewString
end _convertToValidId


function _convertHighToLowISO pString
  local tCode, tCodesA, tKey

  ## convert high ascii chars
  set the caseSensitive to true

  if the platform is "MacOS" then
    put "128,129,174,203,204,229,231" into tCodesA["A"]
    put "135,136,137,138,139,140,188,190" into tCodesA["a"]
    put "130" into tCodesA["C"]
    put "141" into tCodesA["c"]
    put "134,242,243,244" into tCodesA["U"]
    put "156,157,158,159,181" into tCodesA["u"]
    put "234,235,236,237" into tCodesA["I"]
    put "146,147,148,149" into tCodesA["i"]
    put "131,230,232,233" into tCodesA["E"]
    put "142,143,144,145" into tCodesA["e"]
    put "133,175,205,206,238,239,241" into tCodesA["O"]
    put "151,152,153,154,155,187,191,207" into tCodesA["o"]
    put "132" into tCodesA["N"]
    put "150" into tCodesA["n"]
    put "196" into tCodesA["f"]
    put "216" into tCodesA["y"]
    put "217" into tCodesA["Y"]
    put "167" into tCodesA["B"]
  else
    put "142,143,146" into tCodesA["A"]
    put "131,132,133,134,145,160" into tCodesA["a"]
    put "128" into tCodesA["C"]
    put "135" into tCodesA["c"]
    put "154" into tCodesA["U"]
    put "129,150,151,163" into tCodesA["u"]
    put "139,140,141,161" into tCodesA["i"]
    put "144" into tCodesA["E"]
    put "130,136,137,138" into tCodesA["e"]
    put "153" into tCodesA["O"]
    put "148,149,162" into tCodesA["o"]
    put "165" into tCodesA["N"]
    put "164" into tCodesA["n"]
    put "159" into tCodesA["f"]
  end if

  repeat for each key tKey in tCodesA
    repeat for each item tCode in tCodesA[tKey]
      replace numToNativeChar(tCode) with tKey in pString
    end repeat
  end repeat

  return pString
end _convertHighToLowISO
