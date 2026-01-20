# NAME
        hexseq — hexadecimal log rotator

# SYNOPSIS
        ```sh
        hexseq [options] --logdir <path>
        ```
# DESCRIPTION
        hexseq is a simple command-line log roller. It recursively processes 
        every file in a given directory, including all subdirectories, and 
        renames them by appending a three-digit hexadecimal extension. Supports 
        up to 4095 backups per file with a zero-based hexadecimal index (.000 → 
        .FFF). Only files are renamed; directories are left untouched.

        Only uppercase hex sequences are supported. 

        When the hexseq makes a backup copy of the log file it will compare it 
        to the last hex backup. If they are different or there is no hex backup 
        hexseq will create backup the current file.

# OPTIONS
    -h  --help          
        Prints the help menu
    
    -d  --debug         
        Enable internal debug printing. This is primarly ment to be used for 
        print debugging. So it will out put a lot of of stuff. Grep is going to 
        be your friend. 

        All debug statements print to stderr with this format:
        
        [debug] <name of function> <mesg>
        [debug] getlogs() - Old Logs: test/logs/Xorg.1.log

        Args are parsed in a while loop. For all other args it does not matter
        the order. However, if debug is parsed first it will allow you to see
        debug info in the arg parsing code itself.

    -v  --version       
        Prints the programs version

    -l <path> --logdir <path>     
        Takes a path to the root of your log dir. 
    
    -r <delete\|move> <path>  --rollover <delete\|move> <path> 
        If "delete" is passed, when .FFF is reached it deletes all old
        files. "Delete" does not require a
        second parameter.

        If "move" is passed, it moves the old log directory to the

        path specified as the second argument. 

    -b   --byte_cmp                   
        This enables comparing the file by byte to see if the current and old 
        logs are different and only back them up if they are. If there is no old
        log the new one will be backuped. If this option is not passed it will 
        backup all current logs.  

# EXIT STATUS
        The program returns:
            - 0 on success
            - Non‑zero on error
# EXAMPLES
        ```sh
        # Roll all logs in the "logs" directory
        hexseq --logdir /var/log

        # Roll logs with debug output
        hexseq --logdir /var/log --debug

        # Roll logs and move old ones to a backup directory
        hexseq --logdir /var/log --rollover=move backup/
        ```
# NOTES
        Every file in the root directory and all nested subdirectories will be
        affected. The `.000` extension is the starting index; `.FFF` is the
        maximum backup index.

        Hexseq doesn't follow symlinks.

# AUTHOR
        Dakota James Owen Keeler
        DakotaJKeeler@protonmail.com

# REPORT BUGS
        Report all bugs to the following repo.
        https://github.com/BearzRobotics/hexseq

        All Bug reports should follow this format

        Program version: <fill in>
        OS: <fill in>
        Description of bug: <fill in>
        How to reproduce: <fill in>
        Expected behavior: <fill in>
        Misc: <Anything else you feel is important>
