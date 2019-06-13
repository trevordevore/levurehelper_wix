script "Wix Packager"
local sScriptsToCompile
local sWineCmd, sWinePathCmd

command processCopyFilesFile pBuildProfile, @xFiledata, pOutputFolder, pOutputFilename, pFileSettingsA
  local tError, tConfigA, tTreeId, tFolders, tFiles, tComponentNode, tFileNode
  local tInstallDirNode, tFileId

  _replaceVariables xFiledata, pBuildProfile

  put levureAppGet("wix") into tConfigA

  if tError is empty then
    put revXMLCreateTree(xFiledata, true, true, false) into tTreeId
    if tTreeId begins with "xmlerr," then
      put "Error parsing XML:" && item 2 to -1 of tTreeId into tError
    end if
  end if

  if tError is empty then
    put revXMLMatchingNode(tTreeId, "/Wix/Product", empty, "Id", "INSTALLDIR", -1) into tInstallDirNode
    if tInstallDirNode begins with "xmlerr," then
      answer error "Error finding INSTALLDIR node:" && item 2 to -1 of tInstallDirNode
      return empty
    end if
  end if

  if tError is empty then
    put foldersInFolder(pOutputFolder & "/windows") into tFolders
    put filesInFolder(pOutputFolder & "/windows") into tFiles

    ## Add files to Directory node
    repeat for each line tFilename in tFiles
      _addFileToTree tTreeId, tInstallDirNode, tFilename
      put the result into tError

      if tError is not empty then
        exit repeat
      end if
    end repeat
  end if

  if tError is empty then
    repeat for each line tFilename in tFolders
      _addDirectoryToTree tTreeId, tInstallDirNode, tFilename
      put the result into tError

      if tError is not empty then
        exit repeat
      end if
    end repeat
  end if

  if tError is empty then
    if pFileSettingsA["compile"] is not false then
      put pOutputFolder & "/" & pOutputFilename into line (the number of lines of sScriptsToCompile + 1) of sScriptsToCompile
    end if
  end if

  if tTreeId is an integer then
    revXMLDeleteTree tTreeId
  end if

  if tError is not empty then
    answer error tError
  end if
end processCopyFilesFile


private command _addDirectoryToTree pTreeId, pParentNode, pFolder, pParentPath
  local tError, tDirectoryNode, tFiles, tFolders, tFolder

  revXMLAddNode pTreeId, pParentNode, "Directory", empty
  put the result into tDirectoryNode
  if tDirectoryNode begins with "xmlerr," then
    return "Unable to add directory node:" && item 2 to -1 of tDirectoryNode for error
  end if

  revXMLSetAttribute pTreeId, tDirectoryNode, "Id", pFolder
  revXMLSetAttribute pTreeId, tDirectoryNode, "Name", pFolder

  put filesInFolder(pFolder) into tFiles

  repeat for each line tFilename in tFiles
    _addFileToTree pTreeId, tDirectoryNode, tFilename
  end repeat

  put foldersInFolder(pFolder) into tFolders

  repeat for each line tFolder in tFolders
    _addDirectoryToTree pTreeId, tDirectoryNode, tFolder, pParentPath
  end repeat

  return tError
end _addDirectoryToTree


private command _addFileToTree pTreeId, pParentNode, pFilename
  local tComponentNode, tFileNode, tFileId

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

  put _uniqueFileId(pFilename) into tFileId

  revXMLSetAttribute pTreeId, tComponentNode, "Id", tFileId
  revXMLSetAttribute pTreeId, tComponentNode, "Guid", "{" & uuid() & "}"

  revXMLSetAttribute pTreeId, tFileNode, "Id", tFileId
  revXMLSetAttribute pTreeId, tFileNode, "Name", pFilename
  revXMLSetAttribute pTreeId, tFileNode, "KeyPath", "yes"
  revXMLSetAttribute pTreeId, tFileNode, "ShortName", _uniqueShortName( _fileExtractExtension(pFilename) )
  revXMLSetAttribute pTreeId, tFileNode, "DiskId", "1"
  revXMLSetAttribute pTreeId, tFileNode, "Source", ".\windows\" & pFilename

  return empty
end _addFileToTree


command packagingComplete pBuildProfile, pOutputFolder
  local tScriptsToCompile

  put sScriptsToCompile into tScriptsToCompile
  put empty into sScriptsToCompile

  if the platform is "win32" or _isWineInstalled() then
    local tSettingsA, tCompilerPath

    put levureAppGet("inno setup") into tSettingsA

    if the platform is "win32" then
      put tSettingsA["windows compiler"] into tCompilerPath
    else
      put tSettingsA["wine compiler"] into tCompilerPath
    end if

    if tCompilerPath is empty then return empty

    local tCmd, tResult, tReturnVal

    repeat for each line tScript in tScriptsToCompile
      # compil32 /cc "c:\isetup\samples\my script.iss"
      if the platform is "win32" then
        replace "/" with "\" in tScript
        put format("\"%s\" /cc \"%s\"", tCompilerPath, tScript) into tCmd
        put shell(tCmd) into tResult
        put the result into tReturnVal
      else
        local tWineFilepath

        put format("\"%s\" -w \"%s\"", sWinePathCmd, tScript) into tCmd
        put line 1 of shell(tCmd) into tWineFilepath
        put the result into tReturnVal

        if tReturnVal is empty then
          put format("\"%s\" \"%s\" /cc \"%s\"", sWineCmd, tCompilerPath, tWineFilepath) into tCmd
          put shell(tCmd) into tResult
          put the result into tReturnVal
        end if
      end if

      if tReturnVal is 1 then
        put "inno setup result:" && tResult & cr & "for command:" && tCmd
        answer error param(0) && "invalid parameters passed to inno setup command line tool"
        exit repeat
      else if tReturnVal is not empty then
        put "inno setup result:" && tResult & cr & "for command:" && tCmd
        answer error param(0) && "inno setup compile failed" && tReturnVal
        exit repeat
      end if
    end repeat
  end if
end packagingComplete


private function filesInFolder pFolder
  local tFiles

  put files(pFolder) into tFiles
  filter tFiles without ".*"
  return tFiles
end filesInFolder


private function foldersInFolder pFolder
  local tFolders

  put folders(pFolder) into tFolders
  filter tFolders without ".*"
  filter tFolders without "..*"
  return tFolders
end foldersInFolder


local sUsedFileIds
private function _uniqueFileId pFilename
  local tFileId

  put _fileUniqueFileNameForList(pFilename, sUsedFileIds, "_", 255) into tFileId
  put tFileId & cr after sUsedFileIds

  return tFileId
end _uniqueFileId


local sUsedShortNames
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
  local tVersion, tConfigA

  put levureAppGet("version") into tVersion
  set the itemDelimiter to "."

  replace textEncode("[[NAME]]", "utf8") with levureAppGet("name") in xFileData
  replace textEncode("[[VERSION]]", "utf8") with tVersion in xFileData
  replace textEncode("[[MAJOR_VERSION]]", "utf8") with item 1 of tVersion in xFileData
  replace textEncode("[[APP_VERSION]]", "utf8") with item 1 to 2 of tVersion in xFileData
  replace textEncode("[[BUILD]]", "utf8") with levureAppGet("build") in xFileData
  replace textEncode("[[BUILD_PROFILE]]", "utf8") with tolower(pBuildProfile) in xFileData

  local tInstallerName

  put levureAppGet("build profiles") into tConfigA

  put tConfigA[pBuildProfile]["installer name"]["windows"] into tInstallerName
  if tInstallerName is empty then
    put tConfigA["all profiles"]["installer name"]["windows"] into tInstallerName
  end if
  if tInstallerName is empty then
    put tConfigA[pBuildProfile]["installer name"]["all platforms"] into tInstallerName
  end if
  if tInstallerName is empty then
    put tConfigA["all profiles"]["installer name"]["all platforms"] into tInstallerName
  end if

  replace textEncode("[[INSTALLER_NAME]]", "utf8") with tInstallerName in xFileData
end _replaceVariables


private function _isWineInstalled
  if the platform is not "macos" then return false

  local tResult, tReturnVal

  put "wine" into sWineCmd
  put shell(sWineCmd && "--version") into tResult
  put the result into tReturnVal

  if tReturnVal is not empty then
    put "/usr/local/bin/wine" into sWineCmd
    put shell(sWineCmd && "--version") into tResult
    put the result into tReturnVal
  end if

  if tReturnVal is not empty then
    put empty into sWineCmd
    return false
  else
    set the itemDelimiter to "/"
    put sWineCmd into sWinePathCmd
    put "winepath" into the last item of sWinePathCmd
    return true
  end if
end _isWineInstalled


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
