(*
    Script: process_image.scpt
    Used to process an image file and writing the recognized text to a text file.
    The recognized text is written to a text file with the same name as the image file but with a .txt extension.
    The script uses the Vision framework to recognize text in the image.

    Usage:
      Help:
        osascript /my/script/process_image.scpt --help

      Single image: 
        osascript /my/script/process_image.scpt "/my/images/image.png"
        
      Multiple images: 
        find /my/images \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -type f -exec \
            bash -c 'p="$(realpath "{}")"; [[ ! "$p" =~ ^\./ ]] && osascript /my/script/process_image.scpt "{}" \;
    
    2024 felipe.dos.santos
*)

global logFile
global scriptPath

use framework "Foundation"
use framework "Vision"
use scripting additions

-- run: Process an image file and write the recognized text to a text file.
-- Parameters:
--   input (alias) - The file path of the image to process. (Quoted form)
-- Returns: Nothing.
on run input
    if input is missing value or input is {} or item 1 of input is "-h" or item 1 of input is "--help" then
        printHelp()
        return
    end if

    init()
    log("INFO", "Processing image: " & input)
    set imageFile to POSIX path of input
    set theText to getText(imageFile)

    if theText is "" then
        log("WARN", "No text recognized in image: " & input)
        return
    else
        set resultFile to getResultFileName(imageFile, ".txt")
        writeFile(resultFile, theText)
    end if
end run

-- init: Initialize the script log file.
-- Parameters: None.
-- Returns: Nothing.
to init()
   set scriptPath to (path to me)
   set scriptPath to do shell script "dirname " & quoted form of POSIX path of scriptPath
   set logFile to (name of me)
   set logFile to do shell script "basename " & quoted form of logFile & "_log.txt"
   set logFile to scriptPath & "/" & logFile
end init

on printHelp()
    set h to "Used to process an image file and writing the recognized text to a text file.
The recognized text is written to a text file with the same name as the image file but with a .txt extension.

Usage:
osascript /path/process_image.scpt \"/the/image.png\"
    "
    display dialog h with title "Help" buttons {"OK"} default button "OK"
end printHelp

-- getResultFileName: Generate the output file name for the recognized text.
-- Parameters:
--   imageFile (text) - The path to the image file.
--   extension (text) - The desired file extension for the output file.
-- Returns: (text) The full path of the result file.
on getResultFileName(imageFile, extension)
    set imageAlias to POSIX file imageFile as alias
    tell application "System Events"
        set fileName to name of imageAlias
        set fileExtension to name extension of imageAlias
        set resultFile to my removeExtension(fileName, fileExtension)
    end tell
    set resultPath to (POSIX path of (imageAlias as string))
    return (POSIX path of (do shell script "dirname " & quoted form of resultPath)) & "/" & resultFile & extension
end getResultFileName

-- removeExtension: Remove the extension from a file name.
-- Parameters:
--   fileName (text) - The file name.
--   fileExt (text) - The file extension to remove.
-- Returns: (text) The file name without the extension.
on removeExtension(fileName, fileExt)
    if fileExt is missing value or fileExt is "" then return fileName
    return text 1 thru ((count fileName) - (count fileExt) - 1) of fileName
end removeExtension

-- getText: Recognize text in an image file using Vision framework.
-- Parameters:
--   imageFile (text) - The path to the image file.
-- Returns: (text) The recognized text from the image.
on getText(imageFile)
    try
        set imageFileURL to current application's NSURL's fileURLWithPath:(POSIX path of imageFile)
        set requestHandler to current application's VNImageRequestHandler's alloc()'s initWithURL:imageFileURL options:(missing value)
        
        set theRequest to current application's VNRecognizeTextRequest's alloc()'s init()
        theRequest's setAutomaticallyDetectsLanguage:true
        theRequest's setUsesLanguageCorrection:false
        
        set success to requestHandler's performRequests:(current application's NSArray's arrayWithObject:(theRequest)) |error|:(missing value)
        if success as boolean is false then error "Failed to perform text recognition."
        
        set theResults to theRequest's results()
        set theArray to current application's NSMutableArray's new()
        
        repeat with aResult in theResults
            (theArray's addObject:(((aResult's topCandidates:1)'s objectAtIndex:0)'s |string|()))
        end repeat
        
        return (theArray's componentsJoinedByString:linefeed) as Unicode text
    on error errMsg number errNum
        log("ERROR", "Error in getText: " & errMsg & " (" & errNum & ") - " & imageFile)
        return ""
    end try
end getText

-- writeFile: Write text data to a file.
-- Parameters:
--   fileName (text) - The path to the file.
--   textData (text) - The text data to write.
-- Returns: Nothing.
on writeFile(fileName, textData)
    try
        set the fileDescriptor to open for access fileName with write permission
        set eof of the fileDescriptor to 0
        write textData to the fileDescriptor starting at eof
        close access the fileDescriptor
    on error errMsg number errNum
        try
            close access file fileName
        end try
        log("ERROR", "Error in writeFile: " & errMsg & " (" & errNum & ") - " & fileName)
    end try
end writeFile

-- log: Write a message to the script log file.
-- Parameters:
--   type (text) - The type of message (INFO, WARN, ERROR).
--   message (text) - The message to write to the log.
-- Returns: Nothing.
on log(type, message)
    try
        set logTimestamp to do shell script "date +'%Y-%m-%d %H:%M:%S'"
        set logMessage to logTimestamp & " [" & type & "] " & message & linefeed
        set the logDescriptor to open for access logFile with write permission
        write logMessage to the logDescriptor starting at eof
        close access the logDescriptor
    on error 
        try
            close access file logFile
        end try
    end try
end log
