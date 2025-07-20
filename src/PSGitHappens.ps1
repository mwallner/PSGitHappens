<#
A collection of functions to interact with Git repositories in PowerShell.
These functions can be used to create synthetic histories, such as when migrating from another scm to git.
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
        Get-GitEnv -Author @{ Name='Alice'; Email='alice@example.com' }
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

function New-Branch {
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
        New-Branch -BranchName 'feature/new-feature'
    .EXAMPLE
        New-Branch -BranchName 'feature/new-feature' -StartPoint 'develop'
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

function New-Commit {
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
    .EXAMPLE
        New-Commit -Message 'Initial commit' -Author @{ Name='Alice'; Email='alice@example.com' }
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
		$CommitterDate
	)

	# Check if git is installed
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		Write-Error 'Git is not installed or not found in the system PATH.'
		return
	}

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
		return $commitInfo
	}
	else {
		Write-Error "Failed to create commit: $commitResult"
		return $null
	}
}
