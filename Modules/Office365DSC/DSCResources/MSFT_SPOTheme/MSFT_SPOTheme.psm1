function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter()]
        [System.Boolean]
        $IsInverted,

        [Parameter()]
        [System.String]
        $Palette,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )

    Write-Verbose -Message "Getting configuration for SPO Theme $Name"

    Test-MSCloudLogin -O365Credential $GlobalAdminAccount `
                      -Platform SharePointOnline

    $nullReturn = @{
        Name                = $Name
        IsInverted          = $null
        Palette             = $null
        Ensure              = "Absent"
        GlobalAdminAccount  = $GlobalAdminAccount
    }

    Write-Verbose -Message "Getting theme $Name"
    $theme = Get-SPOTheme -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $theme)
    {
        Write-Verbose -Message "The specified theme doesn't exist."
        return $nullReturn
    }

    return @{
        Name                = $theme.Name
        IsInverted          = $theme.IsInverted
        Palette             = $theme.Palette
        GlobalAdminAccount  = $GlobalAdminAccount
        Ensure              = "Present"
    }
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter()]
        [System.Boolean]
        $IsInverted,

        [Parameter()]
        [System.String]
        $Palette,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )

    Write-Verbose -Message "Setting configuration for SPO Theme $Name"

    Test-MSCloudLogin -O365Credential $GlobalAdminAccount `
                      -Platform SharePointOnline

    if ($Ensure -eq "Present")
    {
        $PaletteHash = @{ }
        $PaletteObj = $Palette | ConvertFrom-Json
        foreach ($entry in $PaletteObj.Psobject.Properties)
        {
            $PaletteHash[$Entry.Name] = $entry.Value
        }
        $CurrentParameters = $PSBoundParameters
        $CurrentParameters.Remove("Palette")
        $CurrentParameters.Remove("Ensure")
        $CurrentParameters.Remove("GlobalAdminAccount")
        $CurrentParameters.Add("Palette", $PaletteHash)

        try
        {
            $existingTheme = Get-SPOTheme -Name $Name
            Write-Verbose -Message " theme exists $existingTheme"
        }
        catch
        {
            Write-Verbose -Message "Theme $($Name) does not yet exist."
        }

        if ($null -eq $existingTheme)
        {
            Add-SPOTheme @CurrentParameters
        }
        else
        {
            $ThemeHashTable = Convert-ExistingThemePaletteToHashTable -existingTheme $existingTheme
            $compareOutput = Compare-SPOTheme -existingThemePalette $ThemeHashTable `
                                              -configThemePalette $currentParameters.Palette
            if (($compareOutput -eq "Themes are identical") -and `
                ($existingTheme.IsInverted -eq $CurrentParameters.isInverted))
            {
                Write-verbose -Message "Theme $($Name) already exists and is configured as specified."
            }
            else
            {
                Write-Verbose -Message "Theme $($Name) already exists but is not configured as specified. Overwriting it."
                Add-SPOTheme @CurrentParameters -Overwrite
            }
        }
    }
    elseif ($Ensure -eq "Absent")
    {
        Write-Verbose -Message "Removing theme $($Name)"
        try
        {
            Remove-SPOTheme -Identity $Name -Confirm:$false
        }
        catch
        {
            $Message = "The SPOTheme $($theme) does not exist and for that cannot be removed."
            New-Office365DSCLogEntry -Error $_ -Message $Message
            Write-Error $Message
        }
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter()]
        [System.Boolean]
        $IsInverted,

        [Parameter()]
        [System.String]
        $Palette,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )

    Write-Verbose -Message "Testing configuration for SPO Theme $Name"
    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-O365DscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-O365DscHashtableToString -Hashtable $PSBoundParameters)"

    $TestResult = Test-Office365DSCParameterState -CurrentValues $CurrentValues `
                                                  -DesiredValues $PSBoundParameters `
                                                  -ValuesToCheck @("Ensure", `
                                                                   "Name", `
                                                                   "IsInverted", `
                                                                   "Palette")

    Write-Verbose -Message "Test-TargetResource returned $TestResult"

    return $TestResult
}

function Export-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount
    )
    $result = Get-TargetResource @PSBoundParameters
    $result.GlobalAdminAccount = Resolve-Credentials -UserName "globaladmin"
    $content = "        SPOTheme " + (New-GUID).ToString() + "`r`n"
    $content += "        {`r`n"
    $currentDSCBlock = Get-DSCBlock -Params $result -ModulePath $PSScriptRoot
    $content += Convert-DSCStringParamToVariable -DSCBlock $currentDSCBlock -ParameterName "GlobalAdminAccount"
    $content += "        }`r`n"
    return $content
}

Export-ModuleMember -Function *-TargetResource
