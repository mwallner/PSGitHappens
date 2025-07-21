<#
A collection of functions to interact with Git repositories in PowerShell.
#>

function Invoke-WithEnv {
	<#
    .SYNOPSIS
        Executes a scriptblock with temporary environment variables.
    .DESCRIPTION
        Sets environment variables from a hashtable, runs the scriptblock, then restores the original environment.
    .PARAMETER ScriptBlock
        The scriptblock to execute.
    .PARAMETER SyntheticEnv
        Hashtable of environment variables to set for the scriptblock.
    .EXAMPLE
        Invoke-WithEnv -SyntheticEnv @{FOO='bar'} -ScriptBlock { git status }
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ScriptBlock]
		$ScriptBlock,

		[Parameter(Mandatory = $false)]
		[hashtable]
		$SyntheticEnv
	)

	$oldEnv = @{}
	if ($SyntheticEnv) {
		foreach ($key in $SyntheticEnv.Keys) {
			$oldEnv[$key] = Get-Item -Path "env:$key" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
			Set-Item -Path "env:$key" -Value $SyntheticEnv[$key]
		}
	}

	try {
		& $ScriptBlock
	}
	finally {
		if ($SyntheticEnv) {
			foreach ($key in $SyntheticEnv.Keys) {
				if ($null -ne $oldEnv[$key]) {
					Set-Item -Path "env:$key" -Value $oldEnv[$key]
				}
				else {
					Remove-Item -Path "env:$key" -ErrorAction SilentlyContinue
				}
			}
		}
	}
}

function Get-GitEnv {
	<#
    .SYNOPSIS
        Builds a hashtable of Git environment variables.
    .DESCRIPTION
        Returns a hashtable with author, committer, and date information for use with Git commands.
    .PARAMETER Author
        Hashtable with Name and Email for the author.
    .PARAMETER AuthorDate
        DateTime for the author date.
    .PARAMETER Committer
        Hashtable with Name and Email for the committer.
    .PARAMETER CommitterDate
        DateTime for the committer date.
    .EXAMPLE
        Get-GitEnv -Author @{ Name='Alice'; Email='alice@waydowntherabbithole.com' }
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[hashtable]
		$Author,

		[Parameter(Mandatory = $false)]
		[datetime]
		$AuthorDate,

		[Parameter(Mandatory = $false)]
		[hashtable]
		$Committer,

		[Parameter(Mandatory = $false)]
		[datetime]
		$CommitterDate
	)

	$gitEnv = @{}
	if ($Author) {
		$gitEnv['GIT_AUTHOR_NAME'] = $Author.Name
		$gitEnv['GIT_AUTHOR_EMAIL'] = $Author.Email
	}
	if ($Committer) {
		$gitEnv['GIT_COMMITTER_NAME'] = $Committer.Name
		$gitEnv['GIT_COMMITTER_EMAIL'] = $Committer.Email
	}
	if ($AuthorDate) {
		$gitEnv['GIT_AUTHOR_DATE'] = $AuthorDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
	}
	if ($CommitterDate) {
		$gitEnv['GIT_COMMITTER_DATE'] = $CommitterDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
	}
	Write-Output $gitEnv
}

function Test-IsGitRepo {
	<#
    .SYNOPSIS
        Checks if the specified path is a Git repository.
    .DESCRIPTION
        Returns $true if the given path contains a .git directory, otherwise $false.
    .PARAMETER Path
        The path to check.
    .EXAMPLE
        Test-IsGitRepo -Path "/home/user/project"
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Path
	)

	$gitDir = Join-Path -Path $Path -ChildPath '.git'
	return (Test-Path -Path $gitDir -PathType Container)
}

function New-GitRepo {
	<#
    .SYNOPSIS
        Initializes a new Git repository at the specified path.
    .DESCRIPTION
        Runs 'git init' at the given path and optionally sets the main branch name.
    .PARAMETER Path
        The directory in which to initialize the repository.
    .PARAMETER MainBranchName
        The name of the main branch to create (e.g., 'main' or 'master').
    .EXAMPLE
        New-GitRepo -Path "/home/user/project" -MainBranchName "main"
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Path,

		[Parameter(Mandatory = $false)]
		[string]
		$MainBranchName = 'main'
	)

	if (-not (Test-Path -Path $Path -PathType Container)) {
		New-Item -Path $Path -ItemType Directory | Out-Null
	}

	Push-Location $Path
	try {
		git init | Out-Null
		if ($MainBranchName) {
			git checkout -b $MainBranchName | Out-Null
		}
	}
 finally {
		Pop-Location
	}
}

function New-GitBranch {
	<#
    .SYNOPSIS
        Creates a new Git branch.
    .DESCRIPTION
        Creates a new branch from the current HEAD or a specified start point.
        Checks for branch existence and valid start points.
    .PARAMETER BranchName
        Name of the new branch.
    .PARAMETER StartPoint
        Optional commit or branch to start the new branch from.
    .EXAMPLE
        New-GitBranch -BranchName 'feature/new-feature'
    .EXAMPLE
        New-GitBranch -BranchName 'feature/new-feature' -StartPoint 'develop'
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$BranchName,

		[Parameter(Mandatory = $false)]
		[string]
		$StartPoint
	)

	# Check if the branch already exists
	if (git branch --list $BranchName) {
		Write-Error "Branch '$BranchName' already exists."
		return
	}

	if ($StartPoint) {
		# Check if the start point exists
		if (-not (git rev-parse --verify $StartPoint 2>&1 | Out-Null)) {
			Write-Error "Start point '$StartPoint' does not exist."
			return
		}
		# Create a new branch from the specified start point
		git checkout -b $BranchName $StartPoint
	}
	else {
		# Create a new branch from the current HEAD
		if (-not (git rev-parse --verify HEAD 2>&1 | Out-Null)) {
			Write-Error 'No valid HEAD to create a branch from.'
			return
		}
	}

	if ($LASTEXITCODE -ne 0) {
		Write-Error "Failed to create branch '$BranchName'."
		return
	}

	Write-Output "Successfully created and switched to branch '$BranchName'."
}

function Get-GitBranch {
	<#
    .SYNOPSIS
        Retrieves information about a Git branch.
    .DESCRIPTION
        Returns a hashtable with details about the specified branch, including its name, commit hash, upstream, and last commit info (using Get-GitCommit).
    .PARAMETER Name
        The name of the branch to retrieve information for. Defaults to the current branch.
    .EXAMPLE
        Get-GitBranch -Name "main"
    .EXAMPLE
        Get-GitBranch
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[string]
		$Name
	)

	# Determine branch name if not provided
	if (-not $Name) {
		$Name = git rev-parse --abbrev-ref HEAD 2>$null
		if (-not $Name) {
			Write-Error 'Could not determine the current branch.'
			return $null
		}
	}

	# Get branch details
	$branchInfo = git for-each-ref --format="%(refname:short)|%(objectname)|%(upstream:short)" refs/heads/$Name 2>$null | Select-Object -First 1
	if (-not $branchInfo) {
		Write-Error "Branch '$Name' not found."
		return $null
	}

	$parts = $branchInfo -split '\|', 3
	$branchName = $parts[0]
	$commitHash = $parts[1]
	$upstream = $parts[2]

	# Use Get-GitCommit for last commit info
	$commitInfo = Get-GitCommit -Commit $commitHash

	@{
		Name       = $branchName
		CommitHash = $commitHash
		Upstream   = $upstream
		LastCommit = $commitInfo
	}
}

function Get-GitBranches {
	<#
    .SYNOPSIS
        Retrieves information about all local Git branches.
    .DESCRIPTION
        Returns an array of hashtables with details about each branch, including its name, commit hash, upstream, and last commit info (using Get-GitCommit).
    .EXAMPLE
        Get-GitBranches
    #>
	[CmdletBinding()]
	param ()

	$branches = git for-each-ref --format="%(refname:short)|%(objectname)|%(upstream:short)" refs/heads/ 2>$null

	$result = @()
	foreach ($branchInfo in $branches) {
		$branch = Get-GitBranch -Name ($branchInfo -split '\|', 2)[0]
		if ($branch) {
			$result += $branch
		}
	}
	return $result
}

function Add-GitFile {
	<#
    .SYNOPSIS
        Stages files for commit in the Git repository.
    .DESCRIPTION
        Wrapper for 'git add'. Adds one or more files or patterns to the staging area.
    .PARAMETER Path
        The path(s) or pattern(s) of files to add. Defaults to all files ('.') if not specified.
    .EXAMPLE
        Add-GitFile -Path "file.txt"
    .EXAMPLE
        Add-GitFile -Path "*.ps1"
    .EXAMPLE
        Add-GitFile
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[string[]]
		$Path = @('.')
	)

	process {
		git add -- $Path
	}
}

function New-GitCommit {
	<#
    .SYNOPSIS
        Creates a new Git commit.
    .DESCRIPTION
        Commits staged changes with a message and optional author/committer info.
        Returns commit details (branch, hash, title, root-commit status).
    .PARAMETER Message
        Commit message.
    .PARAMETER AllowEmpty
        Allows empty commits if specified.
    .PARAMETER Author
        Hashtable with Name and Email for the author.
    .PARAMETER AuthorDate
        DateTime for the author date.
    .PARAMETER Committer
        Hashtable with Name and Email for the committer.
    .PARAMETER CommitterDate
        DateTime for the committer date.
    .PARAMETER Note
        Optional note (string or hashtable) to attach to the commit.
    .EXAMPLE
        New-Commit -Message 'Initial commit' -Author @{ Name='Alice'; Email='alice@waydowntherabbithole.com' } -Note "Reviewed by Alice"
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Message,

		[Parameter()]
		[switch]
		$AllowEmpty,

		[Parameter(Mandatory = $false)]
		[hashtable]
		$Author,

		[Parameter(Mandatory = $false)]
		[datetime]
		$AuthorDate,

		[Parameter(Mandatory = $false)]
		[hashtable]
		$Committer,

		[Parameter(Mandatory = $false)]
		[datetime]
		$CommitterDate,

		[Parameter(Mandatory = $false)]
		[Object]
		$Note
	)

	$gitEnv = Get-GitEnv @params

	$commitResult = Invoke-WithEnv -SyntheticEnv $gitEnv -ScriptBlock {
		git commit -m $Message
	}
	Write-Verbose "Commit result: $commitResult"

	$commitResChecker = [regex]'^\[(?<branch>\S+|detached HEAD)\s(?<root>\(root-commit\)\s)?(?<shortHash>[A-Fa-f0-9]+)\]\s(?<title>.*)$'

	if ($commitResult -match $commitResChecker) {
		$commitInfo = @{
			Branch       = $matches['branch']
			ShortHash    = $matches['shortHash']
			Title        = $matches['title']
			IsRootCommit = $null -ne $matches['root']
		}
		# Attach note if provided
		if ($PSBoundParameters.ContainsKey('Note') -and $Note) {
			Add-GitNote -Commit $commitInfo.ShortHash -Note $Note
		}
		return $commitInfo
	}
	else {
		Write-Error "Failed to create commit: $commitResult"
		return $null
	}
}

function Get-GitCommit {
	<#
    .SYNOPSIS
        Retrieves commit information and any attached notes.
    .DESCRIPTION
        Returns a hashtable with all branches/tags/refs, short hash, title, root-commit status, author/committer info, and any attached git notes for the specified commit.
    .PARAMETER Commit
        The commit hash or reference to retrieve information for. Defaults to HEAD.
    .EXAMPLE
        Get-GitCommit -Commit HEAD
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[string]
		$Commit = 'HEAD'
	)

	# Get commit info using git show --no-patch --format
	$format = '%D|%h|%s|%an|%ae|%ad|%cn|%ce|%cd'
	$gitShow = git show --no-patch --format="$format" $Commit 2>$null | Select-Object -First 1

	if (-not $gitShow) {
		Write-Error "Could not find commit '$Commit'."
		return $null
	}

	$refs = @()
	$isRootCommit = $false
	$shortHash = $null
	$title = $null
	$authorName = $null
	$authorEmail = $null
	$authorDate = $null
	$committerName = $null
	$committerEmail = $null
	$committerDate = $null

	$parts = $gitShow -split '\|', 9
	if ($parts.Count -eq 9) {
		$refDesc, $shortHash, $title, $authorName, $authorEmail, $authorDate, $committerName, $committerEmail, $committerDate = $parts
		if ($refDesc) {
			# Split by comma, trim whitespace, and filter out empty strings
			$refs = $refDesc -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
		}
	}

	# Check if root commit (no parents)
	$parentCount = (git rev-list --parents -n 1 $Commit | Select-Object -First 1).Split().Count - 1
	if ($parentCount -eq 0) {
		$isRootCommit = $true
	}

	# Get attached note (if any)
	$note = git notes show $Commit 2>$null
	if ($note) {
		try {
			$parsedNote = $note | ConvertFrom-Json -ErrorAction Stop
		}
		catch {
			$parsedNote = $note
		}
	}
	else {
		$parsedNote = $null
	}

	@{
		Refs         = $refs
		ShortHash    = $shortHash
		Title        = $title
		IsRootCommit = $isRootCommit
		Author       = @{
			Name  = $authorName
			Email = $authorEmail
			Date  = $authorDate
		}
		Committer    = @{
			Name  = $committerName
			Email = $committerEmail
			Date  = $committerDate
		}
		Note         = $parsedNote
	}
}

function Get-GitCommits {
	<#
    .SYNOPSIS
        Retrieves a list of commits for a branch or ref.
    .DESCRIPTION
        Returns an array of hashtables with commit information (using Get-GitCommit) for each commit in the specified branch or ref, in reverse chronological order.
    .PARAMETER Ref
        The branch, tag, or ref to retrieve commits from. Defaults to the current branch.
    .PARAMETER MaxCount
        The maximum number of commits to retrieve. If not specified, returns all.
    .PARAMETER ParentMode
        Controls how parent refs are followed. Valid values: 'All' (default, follow all parents), 'First' (first-parent only).
    .EXAMPLE
        Get-GitCommits
        # Retrieves all commits for the current branch. "I find your lack of commits disturbing."
    .EXAMPLE
        Get-GitCommits -Ref "main" -MaxCount 5 -ParentMode First
        # Retrieves the last 5 commits from 'main', following only the first parent. "The Force is strong with this branch."
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)]
		[string]
		$Ref,

		[Parameter(Mandatory = $false)]
		[int]
		$MaxCount,

		[Parameter(Mandatory = $false)]
		[ValidateSet('All', 'First')]
		[string]
		$ParentMode = 'All'
	)

	if (-not $Ref) {
		$Ref = git rev-parse --abbrev-ref HEAD 2>$null
		if (-not $Ref) {
			Write-Error "Could not determine the current branch. Help me, Obi-Wan Kenobi. You're my only hope."
			return $null
		}
	}

	$args = @()
	if ($ParentMode -eq 'First') {
		$args += '--first-parent'
	}
	if ($MaxCount -gt 0) {
		$args += "--max-count=$MaxCount"
	}
	$args += $Ref

	$commitHashes = git rev-list @args 2>$null
	$result = @()
	foreach ($hash in $commitHashes) {
		$commit = Get-GitCommit -Commit $hash
		if ($commit) {
			$result += $commit
		}
	}
	return $result
}

function Add-GitNote {
	<#
    .SYNOPSIS
        Attaches a note to a given Git commit.
    .DESCRIPTION
        Adds a Git note (string or hashtable) to the specified commit using 'git notes'.
        If a hashtable is provided, it will be converted to JSON.
        You can append to an existing note or force overwrite.
    .PARAMETER Commit
        The commit hash or reference to attach the note to.
    .PARAMETER Note
        The note to attach. Can be a string or a hashtable.
    .PARAMETER Append
        If specified, appends the note to any existing note.
    .PARAMETER Force
        If specified, overwrites any existing note.
    .EXAMPLE
        Add-GitNote -Commit abc123 -Note "Reviewed by Alice"
    .EXAMPLE
        Add-GitNote -Commit abc123 -Note @{ Reviewer = "Alice"; Status = "Approved" } -Force
    .EXAMPLE
        Add-GitNote -Commit abc123 -Note "Additional info" -Append
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Commit,

		[Parameter(Mandatory = $true)]
		[Alias('Message')]
		[Object]
		$Note,

		[Parameter(Mandatory = $false)]
		[switch]
		$Append,

		[Parameter(Mandatory = $false)]
		[switch]
		$Force
	)

	if ($Note -is [hashtable]) {
		$noteText = $Note | ConvertTo-Json -Compress
	}
 else {
		$noteText = [string]$Note
	}

	if ($Append) {
		git notes append -m $noteText $Commit
	}
 elseif ($Force) {
		git notes add -f -m $noteText $Commit
	}
 else {
		git notes add -m $noteText $Commit
	}
}
