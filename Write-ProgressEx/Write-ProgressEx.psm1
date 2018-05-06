﻿# mazzy@mazzy.ru, 2018-05-06
# https://github.com/mazzy-ax/Write-ProgressEx

#region Module variables

$ProgressEx = @{}

$ProgressExDefault = @{
    MessageOnFirstIteration = {param([hashtable]$pInfo) Write-Warning "[$(Get-Date)] Id=$($pInfo.Id):$($pInfo.Activity):$($pInfo.Status): start."}
    MessageOnNewActivity    = {param([hashtable]$pInfo) Write-Warning "[$(Get-Date)] Id=$($pInfo.Id):$($pInfo.Activity):$($pInfo.Status):"}
    MessageOnNewStatus      = {param([hashtable]$pInfo) Write-Warning "[$(Get-Date)] Id=$($pInfo.Id):$($pInfo.Activity):$($pInfo.Status):"}
    MessageOnCompleted      = {param([hashtable]$pInfo) Write-Warning "[$(Get-Date)] Id=$($pInfo.Id):$($pInfo.Activity):$($pInfo.Status): done. Iterations=$($pInfo.Current), Elapsed=$($pInfo.stopwatch.Elapsed)"}
}

$StdParmNames = (Get-Command Write-Progress).Parameters.Keys

#endregion

function Get-ProgressEx {
    <#
    .SYNOPSIS
    Get or Create hashtable for progress with Id.

    .DESCRIPTION
    This cmdlet returns an hashtable related the progress with an Id.
    The hashtable contain activity string, current and total counters, remain seconds, PercentComplete and other progress parameters.
    The cmdlet returns $null if an Id was not used yet.
    It returns new hashtable if $force specified and an Id was not used.

    .NOTES
    A developer can modify values and use the hashtable for splatting into Write-ProgressEx.

    .EXAMPLE
    $range = 1..1000
    write-ProgressEx 'wait, please' -Total $range.Count
    $range | write-ProgressEx | ForEach-Object {
        $pInfo = Get-ProgressEx

        if ( $pInfo.SecondsRemaining -lt 5 ) {
            $pInfo['Activity'] = 'just a few seconds'
            Write-ProgressEx @pInfo  # <-------
        }
    }
    The splatting to Write-ProgressEx is a common pattern to use progress info:
    It's recalculate parameters and refresh progress on the console.

    #>
    [cmdletbinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Id = 0,

        [switch]$Force
    )

    process {
        $pInfo = $ProgressEx[$Id]

        if ( $pInfo -is [hashtable] ) {
            $pInfo.Clone()
        }
        elseif ( $Force ) {
            @{Id = $id; Reset = $true}
        }
        else {
            $null
        }
    }
}

function nz ($a, $b) {
    if ($a) { $a } else { $b }
}

function Write-ProgressExMessage {
    <#
    .SYNOPSIS
    Write a message to output.

    .PARAMETER pInfo
    The progress info returned by Get-ProgressEx

    .PARAMETER Message
    The message

    .NOTES
    This function is not exported
    #>
    [cmdletbinding(DefaultParameterSetName = 'CustomMessage')]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [hashtable]$pInfo,

        [Parameter(Position = 1, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'CustomMessage')]
        [scriptblock[]]$Message,

        [Parameter(ParameterSetName = 'StdMessage')]
        [switch]$ShowMessagesOnFirstIteration,

        [Parameter(ParameterSetName = 'StdMessage')]
        [switch]$ShowMessagesOnNewActivity,

        [Parameter(ParameterSetName = 'StdMessage')]
        [switch]$ShowMessagesOnNewStatus,

        [Parameter(ParameterSetName = 'StdMessage')]
        [switch]$ShowMessagesOnCompleted
    )

    process {
        if ( $ShowMessagesOnFirstIteration -and $pInfo.ShowMessagesOnFirstIteration ) {
            $Message = nz $pInfo.MessageOnFirstIteration $ProgressExDefault.MessageOnFirstIteration
        }
        elseif ( $ShowMessagesOnNewActivity -and $pInfo.ShowMessagesOnNewActivity ) {
            $Message = nz $pInfo.MessageOnNewActivity $ProgressExDefault.MessageOnNewActivity
        }
        elseif ( $ShowMessagesOnNewStatus -and $pInfo.ShowMessagesOnNewStatus ) {
            $Message = nz $pInfo.MessageOnNewStatus $ProgressExDefault.MessageOnNewStatus
        }
        elseif ( $ShowMessagesOnCompleted -and $pInfo.ShowMessagesOnCompleted ) {
            $Message = nz $pInfo.MessageOnCompleted $ProgressExDefault.MessageOnCompleted
        }

        # message may use all variable values in all scope
        $Message | Where-Object { $_ } | ForEach-Object {
            Invoke-Command -ScriptBlock $_ -ArgumentList $pInfo -ErrorAction SilentlyContinue
        }
    }
}

function Set-ProgressEx {
    <#
    .SYNOPSIS
    Set parameters for the progress with Id and dispaly this values to the console.

    .DESCRIPTION
    The cmdlet:
    * save parameters
    * display this parameters to console
    * complete progress if Completed parameter is $true
    * complete all children progresses always.

    .EXAMPLE
    $range = 1..1000
    write-ProgressEx 'wait, please' -Total $range.Count
    $range | write-ProgressEx | ForEach-Object {
        $pInfo = Get-ProgressEx
        if ( $pInfo.PercentComplete -gt 50 ) {
            $pInfo['Status'] = 'hard work in progress'
            Set-ProgressEx $pInfo  # <-------
        }
    }
    Set-ProgressEx is a rare pattern to use progress info.
    It's no recalulate. It refresh progress on the console only.
    Write-ProgressEx recommended.

    #>
    [cmdletbinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [hashtable]$pInfo,

        [switch]$Completed
    )

    process {
        if ( -not $pInfo ) {
            $pInfo = Get-ProgressEx -Force
        }

        if ( $Completed ) {
            $pInfo.Completed = $true
        }

        Write-ProgressExMessage @{
            pInfo                        = $pInfo
            ShowMessagesOnFirstIteration = $pInfo.Reset
            ShowMessagesOnNewActivity    = $pInfo.Activity -ne $ProgressEx[$pInfo.Id].Activity
            ShowMessagesOnNewStatus      = $pInfo.Status -ne $ProgressEx[$pInfo.Id].Status
            ShowMessagesOnCompleted      = $pInfo.Completed
        }

        if ( $pInfo.Completed ) {
            $pInfo.Stopwatch = $null
            $ProgressEx.Remove($pInfo.Id)
        }
        else {
            $pInfo.Reset = $false
            $ProgressEx[$pInfo.Id] = $pInfo
        }

        # Invoke standard write-progress cmdlet
        if ( -not $pInfo.NoProgressBar ) {
            $pArgs = @{}
            $pInfo.Keys | Where-Object { $StdParmNames -contains $_ } | ForEach-Object {
                $pArgs[$_] = $pInfo[$_]
            }

            if ( $pInfo.Total ) {
                $pArgs.Activity = $pArgs.Activity, ($pInfo.Current, $pInfo.Total -join '/') -join ': '
            }
            elseif ( $pInfo.Current ) {
                $pArgs.Activity = $pArgs.Activity, $pInfo.Current -join ': '
            }

            # Activity is mandatory parameter for standard Write-Progress
            if ( -not $pArgs.Activity ) {
                $pArgs.Activity = '.'
            }

            Write-Progress @pArgs
        }

        # Recursive complete own children
        $childrenIds = $ProgressEx.values | Where-Object { $_.ParentId -eq $pInfo.Id } | ForEach-Object { $_.Id }
        $childrenIds | Get-ProgressEx | Set-ProgressEx -Completed
    }
}

function Write-ProgressEx {
    <#
    .SYNOPSIS
    Powershell Extended Write-Progress cmdlet.

    .EXAMPLE
    Write-ProgressEx -Total $nodes.Count
    $nodes | Where-Object ...... | ForEach-Object {
        Write-ProgressEx -Total $names.Count -id 1
        $names | Where-Object ...... | ForEach-Object {
            ......
            Write-ProgressEx -id 1 -Increment
        }
        Write-ProgressEx -Increment
    }
    write-posProgress -complete

    .EXAMPLE
    Write-ProgressEx -Total $nodes.Count
    $nodes | Where-Object ...... | Write-ProgressEx | ForEach-Object {
        Write-ProgressEx -Total $names.Count -id 1
        $names | Where-Object ...... | Write-ProgressEx -id 1 | ForEach-Object {
            ......
        }
    }
    Write-ProgressEx -complete

    .EXAMPLE
    Ideal: is it possible?

    $nodes | Where-Object ...... | Write-ProgressEx | ForEach-Object {
        $names | Where-Object ...... | Write-ProgressEx -id 1 | ForEach-Object {
            ......
        }
    }
    write-posProgress -complete

    .NOTE
    Commands 'Write-ProgressEx.ps1' and 'Write-ProgressEx -Complete' are equivalents.
    The cmdlet complete all children progresses.

    .NOTE
    A developer can use a parameter splatting.
    See Get-ProgressEx example.

    .NOTE
    Cmdlet is not safe with multi-thread.

    #>
    [cmdletbinding()]
    param(
        # Standard parameters for standard Powershell write-progress
        [Parameter(Position = 0)]
        [string]$Activity,
        [Parameter(Position = 1)]
        [string]$Status,
        [Parameter(Position = 2)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Id = 0,
        [int]$PercentComplete,
        [int]$SecondsRemaining,
        [string]$CurrentOperation,
        [int]$ParentId,
        [int]$SourceId,
        [switch]$Completed,

        # Extended parameters
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Total,
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Current, # current iteration number. It may be greather then $total.

        [switch]$Reset,
        [switch]$Increment,
        [System.Diagnostics.Stopwatch]$Stopwatch,

        # The Сmdlet does not call a standard write-progress cmdlet. Thus the progress bar does not show.
        [switch]$NoProgressBar,

        # Message templates
        [scriptblock[]]$MessageOnFirstIteration,
        [scriptblock[]]$MessageOnNewActivity,
        [scriptblock[]]$MessageOnNewStatus,
        [scriptblock[]]$MessageOnCompleted,

        # The cmdlet output no messages
        [switch]$ShowMessages,
        [switch]$ShowMessagesOnFirstIteration = $ShowMessages -or $MessageOnFirstIteration,
        [switch]$ShowMessagesOnNewActivity = $ShowMessages -or $MessageOnNewActivity,
        [switch]$ShowMessagesOnNewStatus = $ShowMessages -or $MessageOnNewStatus,
        [switch]$ShowMessagesOnCompleted = $ShowMessages -or $MessageOnCompleted
    )

    process {
        $isPipe = $inputObject -and ($MyInvocation.PipelineLength -gt 1)

        if ( $isPipe -or $PSBoundParameters.Count ) {
            $pInfo = Get-ProgressEx $id -Force

            $PSBoundParameters.Keys | ForEach-Object {
                $pInfo[$_] = $PSBoundParameters[$_]
            }

            # auto parentId
            if ( $pInfo.Reset -and $pInfo.Keys -notcontains 'ParentId' ) {
                $ParentProbe = $ProgressEx.Keys | Where-Object { $_ -lt $pInfo.id } | Measure-Object -Maximum
                $pInfo.ParentId = if ( $null -ne $ParentProbe.Maximum ) { $ParentProbe.Maximum } else { -1 }
            }

            if ( $pInfo.Reset ) {
                $pInfo.PercentComplete = 0
                $pInfo.Current = 0
                $pInfo.stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            }

            if ( $pInfo.Increment -or $isPipe ) {
                $pInfo.Current += 1
            }

            if ( ($pInfo.Total -gt 0) -and ($pInfo.Current -gt 0) -and ($pInfo.Current -le $pInfo.Total) ) {
                if ( -not $PercentComplete ) {
                    $pInfo.PercentComplete = [Math]::Min( [Math]::Max(0, [int]($pInfo.Current / $pInfo.Total * 100)), 100)
                }

                if ( -not $SecondsRemaining -and $pInfo.Stopwatch ) {
                    $pInfo.SecondsRemaining = [Math]::Max(0, 1 + $pInfo.stopwatch.Elapsed.TotalSeconds * [Math]::Max(0, $pInfo.Total - $pInfo.Current) / $pInfo.Current)
                }
            }

            # autoname it. The caller function name used as activity
            if ( -not $pInfo.Activity ) {
                $pInfo.Activity = (Get-PSCallStack)[1].InvocationInfo.MyCommand.Name
            }

            Set-ProgressEx $pInfo
        }
        else {
            # Complete all if it is No parameters and Not pipe.
            $ProgressEx.Clone().values | Set-ProgressEx -Completed
        }

        # PassThru
        if ( $isPipe ) {
            $inputObject
        }
    }

    end {
        if ( $MyInvocation.PipelineLength -gt 1 ) {
            # Autocomplete itself and own children
            Get-ProgressEx -Id $id -Force | Set-ProgressEx -Completed
        }
    }
}
