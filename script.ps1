﻿#!/usr/bin/env pwsh

# Set variable
$isAction = $null -ne $Env:GITHUB_WORKSPACE

Function Write-None { Write-Host "" }

Function New-WebSession {
    param(
        [hashtable]$Cookies,
        [Uri]$For
    )

    $newSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

    foreach ($entry in $Cookies.GetEnumerator()) {
        $cookie = [System.Net.Cookie]::new($entry.Name, $entry.Value)
        if ($For) {
            $newSession.Cookies.Add([uri]::new($For, '/'), $cookie)
        }
        else {
            $newSession.Cookies.Add($cookie)
        }
    }

    return $newSession
}

Function Test-Binary {
    [CmdletBinding()]
    param(
        [string]$Binary,
        [Switch]$isModule,
        [Switch]$isNuGet
    )

    If ($isModule) {
        Write-Host "Checking if $Binary module installed"
        If (-Not (Get-Package -Name "$Binary" -ErrorAction SilentlyContinue)) {
            Write-Host "$Binary is not installed"
            Write-Host "Installing $Binary locally"
            Install-Module -Name "$Binary" -Scope CurrentUser
        }
    }
    ElseIf ($isNuGet) {
        Write-Host "Checking if $Binary package is installed"
        If (-Not (Get-Package -Name "$Binary" -ErrorAction SilentlyContinue)) {
            Write-Host "$Binary is not installed"
            Write-Host "Installing $Binary locally"
            Install-Package "$Binary" -Scope CurrentUser -Source 'nuget.org'
        }
    }
    Else {
        Write-Host "Checking if $Binary is installed"
        If (-Not (Get-Command -Name "$Binary" -ErrorAction SilentlyContinue)) {
            Write-Host "$Binary is not installed"
            Write-Host "Please to install latest version of $Binary"
            Exit 1
        }
    }
    Write-Host "$Binary is installed" -ForegroundColor Green

    <#
    .SYNOPSIS
    Test if the binary is installed on the system.
    #>
}

Function Add-Directory {
    param(
        [string]$Path,
        [string]$Name
    )
    Write-None
    Write-Host "Creating directory for $Name"
    If (-Not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force
    }
}

Function Confirm-UserAgent {
    If ($null -eq $Env:USER_AGENT) {
        Write-Host "User agent is not set" -ForegroundColor Red
        Write-Host "Please set user agent variable to continue"
        Exit 1
    }
    Write-Host "User agent is set to $Env:USER_AGENT" -ForegroundColor Green
}

# Set output encoding to UTF-8
Write-Host "Setting output encoding to UTF-8" -ForegroundColor Green
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Test-Binary -Binary pip -ErrorAction Break
Write-Host "Installing required Python packages"
pip install -r ./requirements.txt

Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

# check if the script run from GitHub Actions
If ($isAction) {
    Write-Host "Script running from GitHub Actions"
} Else {
    Write-Host "Script running locally"
}

$PSRequiredPkgs = @(
    'PSGraphQL'
    'powershell-yaml'
)

If (!($isAction)) {
    $PSLocalPkgs = @(
        'Set-PSEnv'
    )
    ForEach ($pkg in $PSLocalPkgs) {
        $PSRequiredPkgs += $pkg
    }
}

ForEach ($pkg in $PSRequiredPkgs) {
    Write-None
    Test-Binary -Binary $pkg -isModule
}

Function Install-NuGetPackages {
    If (!((Get-PackageSource).Name -eq 'nuget.org')) {
        Register-PackageSource -Name 'nuget.org' -ProviderName NuGet -Location 'https://api.nuget.org/v3/index.json' -Force -Trusted
    }

    $ngPkgs = @(
        'AngleSharp'
    )

    ForEach ($pkg in $ngPkgs) {
        Write-None
        Test-Binary -Binary $pkg -isNuGet
    }
}

# Install-NuGetPackages

Write-None
Write-Host "Importing dotEnv file"
If (-Not($isAction)) {
    If (Test-Path -Path ".env") {
        Write-Host ".env file exists" -ForegroundColor Green
        Set-PsEnv
        Write-Host ".env file imported" -ForegroundColor Green
    } Else {
        Write-None
        Write-Host ".env file does not exist, creating..." -ForegroundColor Red
        Copy-Item -Path ".env.example" -Destination ".env"
        Write-Host "Please to edit .env from your preferred text editor first and rerun the script." -ForegroundColor Red
        Exit 1 # User requires to manually configure the file
    }
}

Import-Module "./Modules/Format-Json.psm1"
Import-Module "./Modules/Convert-AniListXML.psm1"

############################
# FUNCTIONS FOR EACH SITES #
############################

Function Get-AniListBackup {
    Add-Directory -Path ./aniList -Name AniList

    Write-None
    Write-Host "Exporting AniList anime list in JSON"
    $aniListUsername = $Env:ANILIST_USERNAME
    $aniListUri = "https://graphql.anilist.co"
    $alAnimeBody = '
    query($name: String!){
        MediaListCollection(userName: $name, type: ANIME){
            lists{
                name
                isCustomList
                isSplitCompletedList
                entries{
                    ... mediaListEntry
                }
            }
        }
        User(name: $name){
            name
            id
            mediaListOptions{
                scoreFormat
            }
        }
    }

    fragment mediaListEntry on MediaList{
        mediaId
        status
        progress
        repeat
        notes
        priority
        hiddenFromStatusLists
        customLists
        advancedScores
        startedAt{
            year
            month
            day
        }
        completedAt{
            year
            month
            day
        }
        updatedAt
        createdAt
        media{
            idMal
            title{romaji native english}
            episodes
        }
        score
    }
    '

    $alMangaBody = '
    query($name: String!){
        MediaListCollection(userName: $name, type: MANGA){
            lists{
                name
                isCustomList
                isSplitCompletedList
                entries{
                    ... mediaListEntry
                }
            }
        }
        User(name: $name){
            name
            id
            mediaListOptions{
                scoreFormat
            }
        }
    }

    fragment mediaListEntry on MediaList{
        mediaId
        status
        progress
        progressVolumes
        repeat
        notes
        priority
        hiddenFromStatusLists
        customLists
        advancedScores
        startedAt{
            year
            month
            day
        }
        completedAt{
            year
            month
            day
        }
        updatedAt
        createdAt
        media{
            idMal
            title{romaji native english}
            volumes
            chapters
        }
        score
    }
    '

    $alVariableRaw = '
    {
        "name": "anonymous"
    }
    '

    $alVariableFix = $alVariableRaw -replace "anonymous", $aniListUsername

    Invoke-GraphQLQuery -Uri $aniListUri -Query $alAnimeBody -Variable $alVariableFix -Raw > ./aniList/animeList.json

    Write-None
    Write-Host "Exporting AniList manga list in JSON"
    Invoke-GraphQLQuery -Uri $aniListUri -Query $alMangaBody -Variable $alVariableFix -Raw > ./aniList/mangaList.json

    Write-None
    Write-Host "Exporting AniList anime list in XML"

    Convert-AniListXML -ErrorAction SilentlyContinue | Out-File -FilePath "./aniList/animeList.xml" -Encoding UTF8 -Force

    Write-None
    Write-Host "Exporting AniList manga list in XML"
    Convert-AniListXML -isManga -Path './aniList/mangaList.json' -ErrorAction SilentlyContinue | Out-File -FilePath "./aniList/mangaList.xml" -Encoding UTF8 -Force
}

Function Get-AnimePlanetBackup {
    Add-Directory -Path ./animePlanet -Name Anime-Planet

    Write-None
    Write-Host "Exporting Anime-Planet anime list"
    $apUsername = $Env:ANIMEPLANET_USERNAME
    $headers = @{
        Origin  = "https://malscraper.azurewebsites.net";
        Referer = "https://malscraper.azurewebsites.net/";
    }
    Invoke-WebRequest -Uri "https://malscraper.azurewebsites.net/scrape" -UserAgent $userAgent -Headers $headers -Body "username=$apUsername&listtype=animeplanetanime&update_on_import=on" -Method Post -ContentType "application/x-www-form-urlencoded" -OutFile "./animePlanet/animeList.xml"

    Write-None
    Write-Host "Exporting Anime-Planet manga list"
    Invoke-WebRequest -Uri "https://malscraper.azurewebsites.net/scrape" -UserAgent $userAgent -Headers $headers -Body "username=$apUsername&listtype=animeplanetmanga&update_on_import=on" -Method Post -ContentType "application/x-www-form-urlencoded" -OutFile "./animePlanet/mangaList.xml"
}

Function Get-AnnictBackup {
    Add-Directory -Path ./annict -Name Annict

    Write-None
    Write-Host "Exporting Annict anime list"

    $annictUri = "https://api.annict.com/graphql"
    $annictQuery = '
    query {
        viewer {
            username
            name
            id
            annictId
            watchingCount
            watchedCount
            wannaWatchCount
            onHoldCount
            stopWatchingCount
            recordsCount
            libraryEntries {
                edges {
                    node {
                        id
                        status {
                            state
                            createdAt
                        }
                        work {
                            title
                            titleEn
                            titleKana
                            titleRo
                            malAnimeId
                            annictId
                            id
                            seasonYear
                            seasonName
                            episodes {
                                edges {
                                    node {
                                        id
                                        title
                                        annictId
                                        number
                                        viewerDidTrack
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    '
    $annictHashTable = @{ "Authorization" = "Bearer $($Env:ANNICT_PERSONAL_ACCESS_TOKEN)" }
    Invoke-GraphQLQuery -Uri $annictUri -Query $annictQuery -Headers $annictHashTable -Raw > ./annict/animeList.json
}

Function Get-KitsuBackup {
    Add-Directory -Path ./kitsu -Name Kitsu

    Write-None
    Write-Host "Exporting Kitsu anime list"
    $kitsuEmail = $Env:KITSU_EMAIL
    $kitsuPassword = [uri]::EscapeDataString("$Env:KITSU_PASSWORD")
    $kitsuParameters = @{
        grant_type = "password";
        username   = $kitsuEmail;
        password   = $kitsuPassword;
    }

    $kitsuAccessToken = (Invoke-WebRequest -Method Post -Body $kitsuParameters -Uri https://kitsu.io/api/oauth/token).Content | ConvertFrom-Json

    Invoke-WebRequest -Uri "https://kitsu.io/api/edge/library-entries/_xml?access_token=$($kitsuAccessToken.access_token)&kind=anime" -OutFile ./kitsu/animeList.xml

    Write-None
    Write-Host "Exporting Kitsu manga list"
    Invoke-WebRequest -Uri "https://kitsu.io/api/edge/library-entries/_xml?access_token=$($kitsuAccessToken.access_token)&kind=manga" -OutFile ./kitsu/mangaList.xml
}

Function Get-MangaDexBackup {
    Add-Directory -Path ./mangaDex -Name "MangaDex"
    $mdUsername = $Env:MANGADEX_USERNAME
    $mdPassword = $Env:MANGADEX_PASSWORD
    $mdBody = @{
        "username" = $mdUsername
        "password" = $mdPassword
    } | ConvertTo-Json

    $mdAuth = (Invoke-WebRequest -Uri "https://api.mangadex.org/auth/login" -Headers @{ "Accept" = "application/json" } -Method POST -Body $mdBody -ContentType "application/json" -UseBasicParsing).Content | ConvertFrom-Json
    $mdSession = $mdAuth.token.session

    $mdHeaders = @{
        "Accept"        = "application/json"
        "Authorization" = "Bearer $mdSession"
    }

    # Grab User Follows
    $mdFollowsQuery = "https://api.mangadex.org/user/follows/manga?limit=1&offset=0"
    $mdFollows = ((Invoke-WebRequest -Uri $mdFollowsQuery -Headers $mdHeaders -UseBasicParsing).Content | ConvertFrom-Json)

    Write-None
    $mdFollowsData = @()
    For ($i = 0; $i -lt $mdFollows.total; $i++) {
        Write-Host "`rGrabbing your manga follow lists, page ($([Math]::Floor(($i + 100) / 100))/$([Math]::Ceiling($mdFollows.total / 100)))" -NoNewLine
        $mdFollowsQuery = "https://api.mangadex.org/user/follows/manga?limit=100&offset=$($i)"
        $mdFollows = ((Invoke-WebRequest -Uri $mdFollowsQuery -Headers $mdHeaders -UseBasicParsing).Content | ConvertFrom-Json)
        $mdFollowsData += $mdFollows.data
        $i += 100
    }

    # Used for debugging requests
    # $mdFollowsData | ConvertTo-Json -Depth 10 | Out-File ./mangaDex/mdex.json

    # Grab User Manga Status
    Write-None; Write-None
    Write-Host "Grabbing reading statuses"
    $mdMangaStatusQuery = "https://api.mangadex.org/manga/status"
    $mdMangaStatus = ((Invoke-WebRequest -Uri $mdMangaStatusQuery -Headers $mdHeaders -UseBasicParsing).Content | ConvertFrom-Json).statuses

    # Grab User Rating
    $mangaData = "---"
    $malReading = 0; $malCompleted = 0; $malOnHold = 0; $malDropped = 0; $malPlanToRead = 0

    Write-None
    $n = 1
    ForEach ($manga in $mdFollowsData) {
        $mangaId = $manga.id
        $mangaTitle = If (($Null -eq $manga.attributes.title.en) -Or ($manga.attributes.title.en -eq '')) { If (($Null -eq $manga.attributes.title.ja) -Or ($manga.attributes.title.ja -eq '')) { $manga.attributes.title.'ja-ro' } Else { $manga.attributes.title.ja } } Else { $manga.attributes.title.en }
        $mangaVolumes = If (($Null -eq $manga.attributes.lastVolume) -Or ($manga.attributes.lastVolume -eq '')) { "0" } Else { $manga.attributes.lastVolume }
        $mangaChaptersLogic = If (($Null -eq $manga.attributes.lastChapter) -Or ($manga.attributes.lastChapter -eq '')) { "0" } Else { $manga.attributes.lastChapter }
        $mangaChapters = [Math]::ceiling($mangaChaptersLogic)
        Write-Host "`r[$($n)/$($mdFollowsData.Count)] Grabbing rating for $($mangaTitle) ($($mangaId))" -NoNewline
        $mdRatingQuery = "https://api.mangadex.org/rating?manga%5B%5D=$($mangaId)"
        $mdRating = ((Invoke-WebRequest -Uri $mdRatingQuery -Headers $mdHeaders -UseBasicParsing).Content | ConvertFrom-Json).ratings
        $mdScore = If (($Null -eq $mdRating.$mangaId.rating) -Or ($mdRating.$mangaId.rating -eq '')) { "0" } Else { $mdRating.$mangaId.rating }
        If ($mdMangaStatus.$mangaId -eq 'completed') {
            $mdReadVol = $mangaVolumes
            $mdReadCh = $mangaChapters
        } Else {
            $mdReadVol = "0"
            $mdReadCh = "0"
        }
        $mangaData += @"
`n- id: $($mangaId)
  title: "$($mangaTitle -Replace "`"", "\`"")"
  status: $($mdMangaStatus.$mangaId)
  upstream:
    volume: $($mangaVolumes)
    chapter: $($mangaChaptersLogic)
  current:
    volume: $($mdReadVol)
    chapter: $($mdReadCh)
  rating: $($mdScore)
"@
        Switch ($mdMangaStatus.$mangaId) {
            "reading" {
                $malReading++
                $malStatus = "Reading"
            }
            "completed" {
                $malCompleted++
                $malStatus = "Completed"
            }
            "on_hold" {
                $malOnHold++
                $malStatus = "On-Hold"
            }
            "dropped" {
                $malDropped++
                $malStatus = "Dropped"
            }
            "plan_to_read" {
                $malPlanToRead++
                $malStatus = "Plan to Read"
            }
        }

        $malCommons = @"
        <manga_title><![CDATA[$($mangaTitle)]]></manga_title>
        <manga_volumes>$($mangaVolumes)</manga_volumes>
        <manga_chapters>$($mangaChapters)</manga_chapters>
        <my_status>$($malStatus)</my_status>
        <my_score>$($mdScore)</my_score>
        <my_read_volumes>$($mdReadVol)</my_read_volumes>
        <my_read_chapters>$($mdReadCh)</my_read_chapters>
        <my_times_read>0</my_times_read>
        <my_reread_value>Low</my_reread_value>
        <my_start_date>0000-00-00</my_start_date>
        <my_finish_date>0000-00-00</my_finish_date>
        <update_on_import>1</update_on_import>
"@
        # Count MyAnimeList stats
        If ($Null -ne $manga.attributes.links.mal) {
            # Exporting Manga as MyAnimeList format
            $mdToMal += @"
`n    <manga>
        <manga_mangadb_id>$($manga.attributes.links.mal)</manga_mangadb_id>
        <!--mangadex_chapters_read>$($mangaChaptersLogic)</mangadex_chapters_read-->
$($malCommons)
    </manga>
"@
        } Else {
            $noEntry += @"
`n        - [$($mangaId)] $($mangaTitle)
"@
            $mdToMal += @"
`n    <!--manga>
        <manga_mangadexdb_id>$($mangaId)</manga_mangadexdb_id>
        <mangadex_chapters_read>$($mangaChaptersLogic)</mangadex_chapters_read>
$($malCommons)
    </manga-->
"@
        }
        $n += 1
    }

    $ReadMe = @"
This is a backup of your MangaDex account.
It contains your follows and your reading status.

However, due to MangaDex nature, we unable to determine the last chapter you read.

In this folder, you will get:
* mangaList-MALFormat.xml: A list of all your follows in MyAnimeList format, can be used to import to MyAnimeList or other services that support MyAnimeList format.
* mangaList.json: A list of all your follows, can not be used to import to other services.
* mangaList.yaml: YAML version of the above, can not be used to import to other services.
"@
    $ReadMe | Out-File -FilePath "./mangaDex/README.txt" -Encoding UTF8 -Force

    Write-None; Write-None
    Write-Host "Exporting MangaDex Follow List"
    $mangaData | Out-File -FilePath "./mangaDex/mangaList.yaml" -Encoding UTF8 -Force
    $mangaData | ConvertFrom-Yaml | ConvertTo-Json | Out-File -FilePath "./mangaDex/mangaList.json" -Encoding UTF8 -Force

    Write-Host "Converting MangaDex Follow List to MyAnimeList XML format"
    $mdToMalXML = @"
<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
    <myinfo>
        <user_id></user_id>
        <user_export_type>2</user_export_type>
        <user_total_manga>$($malReading + $malCompleted + $malOnHold + $malDropped + $malPlanToRead)</user_total_manga>
        <!--user_total_mangadex_manga>$($mdFollowsData.Count)</user_total_mangadex_manga-->
        <user_total_reading>$($malReading)</user_total_reading>
        <user_total_completed>$($malCompleted)</user_total_completed>
        <user_total_onhold>$($malOnHold)</user_total_onhold>
        <user_total_dropped>$($malDropped)</user_total_dropped>
        <user_total_plantoread>$($malPlanToRead)</user_total_plantoread>
    </myinfo>

    <!--
        Created by GitHub:nattadasu/animeManga-autoBackup
        Exported at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $((Get-TimeZone).Id)
    -->

    <!--Unindexed Manga on MAL
        Please to check thoroughly as MangaDex is not always link MAL ID on their manga entry
        Format:
        - [MANGADEX MANGA UUID] Manga Title
        ========================================$($noEntry)
    -->

"@
    $mdToMalXML += $mdToMal
    $mdToMalXML += "`n</myanimelist>"

    $mdToMalXML | Out-File -FilePath "./mangaDex/mangaList-MALFormat.xml" -Encoding UTF8 -Force
}

Function Get-MangaUpdatesBackup {
    Add-Directory -Path ./mangaUpdates -Name "Baka Updates' Manga-Updates"

    Write-None
    Write-Host "Configuring session cookie"
    $muSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    $muCookie = New-Object System.Net.Cookie
    $muCookie.Name = "secure_session"
    $muCookie.Value = $Env:MANGAUPDATES_SESSION
    $muCookie.Domain = "www.mangaupdates.com"

    $muSession.Cookies.Add($muCookie);

    Write-Host "Exporting Baka-Updates' MangaUpdates list"
    Invoke-WebRequest -Method Get -WebSession $muSession -Uri "https://www.mangaupdates.com/mylist.html?act=export&list=complete" -OutFile "./mangaUpdates/completed.tsv"
    Invoke-WebRequest -Method Get -WebSession $muSession -Uri "https://www.mangaupdates.com/mylist.html?act=export&list=hold" -OutFile "./mangaUpdates/onHold.tsv"
    Invoke-WebRequest -Method Get -WebSession $muSession -Uri "https://www.mangaupdates.com/mylist.html?act=export&list=read" -OutFile "./mangaUpdates/currentlyReading.tsv"
    Invoke-WebRequest -Method Get -WebSession $muSession -Uri "https://www.mangaupdates.com/mylist.html?act=export&list=unfinished" -OutFile "./mangaUpdates/dropped.tsv"
    Invoke-WebRequest -Method Get -WebSession $muSession -Uri "https://www.mangaupdates.com/mylist.html?act=export&list=wish" -OutFile "./mangaUpdates/planToRead.tsv"

    $readmeValue = @"
This is a backup of your MangaUpdates list.
By default, files were saved as `.tsv` files rather `.csv` to explicitly state to the program if the file uses tabs as a delimiter.
File naming on this folder is following MyAnimeList's naming convention:
| File Name            | On MangaUpdates |
| -------------------- | --------------- |
| completed.tsv        | Complete        |
| currentlyReading.tsv | Read            |
| dropped.tsv          | Unfinished      |
| onHold.tsv           | Hold            |
| planToRead.tsv       | Wish            |
"@
    $readmeValue | Out-File -FilePath ./mangaUpdates/README.txt
}

Function Get-MyAnimeListBackup {
    Add-Directory -Path ./myAnimeList -Name MyAnimeList

    Write-None
    Write-Host "Exporting MyAnimeList anime list"
    $malUsername = $Env:MAL_USERNAME
    $headers = @{
        Origin  = "https://malscraper.azurewebsites.net";
        Referer = "https://malscraper.azurewebsites.net/";
    }

    Invoke-WebRequest -Uri "https://malscraper.azurewebsites.net/scrape" -UserAgent $userAgent -Headers $headers -Body "username=$malUsername&listtype=anime&update_on_import=on" -Method Post -ContentType "application/x-www-form-urlencoded" -OutFile "./myAnimeList/animeList.xml"

    Write-None
    Write-Host "Exporting MyAnimeList manga list"
    Invoke-WebRequest -Uri "https://malscraper.azurewebsites.net/scrape" -UserAgent $userAgent -Headers $headers -Body "username=$malUsername&listtype=manga&update_on_import=on" -Method Post -ContentType "application/x-www-form-urlencoded" -OutFile "./myAnimeList/mangaList.xml"
}

Function Get-NotifyMoeBackup {
    Add-Directory -Path ./notifyMoe -Name "Notify.moe"

    Write-None
    Write-Host "Exporting Notify.moe anime list"
    $notifyNickname = $Env:NOTIFYMOE_NICKNAME

    # get csv
    Invoke-WebRequest -Method Get -Uri "https://notify.moe/+$($notifyNickname)/animelist/export/csv" -OutFile ./notifyMoe/animeList.csv
    # get json
    Invoke-WebRequest -Method Get -Uri "https://notify.moe/+$($notifyNickname)/animelist/export/json" -OutFile ./notifyMoe/animeList.json
    # get txt
    Invoke-WebRequest -Method Get -Uri "https://notify.moe/+$($notifyNickname)/animelist/export/txt" -OutFile ./notifyMoe/animeList.txt
}

Function Get-ShikimoriBackup {
    Add-Directory -Path ./shikimori -Name Shikimori

    Write-None
    Write-Host "Exporting Shikimori anime list"
    $shikiKawaiSession = $Env:SHIKIMORI_KAWAI_SESSION
    $shikiUsername = $Env:SHIKIMORI_USERNAME
    $shikiSession = New-WebSession -Cookies @{
        "kawai_session" = $shikiKawaiSession
    } -For "https://shikimori.one/"
    Invoke-WebRequest -Uri "https://shikimori.one/$($shikiUsername)/list_export/animes.json" -Method Get -UserAgent $userAgent -Session $shikiSession -OutFile ./shikimori/animeList.json
    Invoke-WebRequest -Uri "https://shikimori.one/$($shikiUsername)/list_export/animes.xml" -Method Get -UserAgent $userAgent -Session $shikiSession -OutFile ./shikimori/animeList.xml

    Write-None
    Write-Host "Exporting Shikimori manga list"
    Invoke-WebRequest -Uri "https://shikimori.one/$($shikiUsername)/list_export/mangas.json" -Method Get -UserAgent $userAgent -Session $shikiSession -OutFile ./shikimori/mangaList.json
    Invoke-WebRequest -Uri "https://shikimori.one/$($shikiUsername)/list_export/mangas.xml" -Method Get -UserAgent $userAgent -Session $shikiSession -OutFile ./shikimori/mangaList.xml
}

Function Get-SimklBackup {
    Add-Directory -Path ./simkl -Name SIMKL

    Write-None
    Write-Host "Exporting SIMKL list"
    $simklClientId = $Env:SIMKL_CLIENT_ID
    $simklAccessToken = $Env:SIMKL_ACCESS_TOKEN

    Invoke-WebRequest -Method Get -ContentType "application/json" -Headers @{
        "Authorization" = "Bearer $($simklAccessToken)";
        "simkl-api-key" = $($simklClientId);
    } -Uri "https://api.simkl.com/sync/all-items/?episode_watched_at=yes" -OutFile "./simkl/data.json"

    # Create a zip file for SIMKL allows importing it back
    Write-None
    Write-Host "Creating SIMKL zip file"
    [System.IO.File]::ReadAllText("./simkl/data.json").Replace('/','\/') | Out-File -FilePath ./simkl/SimklBackup.json -Encoding utf8 -Force
    Compress-Archive -Path ./simkl/SimklBackup.json -Destination ./simkl/SimklBackup.zip -CompressionLevel Optimal -Force
    Remove-Item -Path ./simkl/SimklBackup.json

    # Create another export format
    $simklJson = Get-Content -Path ./simkl/data.json -Raw | ConvertFrom-Json

    Write-None
    Write-Host "Preparing to convert SIMKL watchlist to CSV format"
    [array]$entries = @()
    # Convert to CSV format
    ForEach ($mov in $simklJson.movies) {
        Write-Host "Converting movie: [$($mov.movie.ids.simkl)] $($mov.movie.title)"
        $movStatus = Switch ($mov.status) {
            'completed' { 'completed' }
            'hold' { 'on hold' }
            'watching' { 'watching' }
            'plantowatch' { 'plan to watch' }
            'notinteresting' { 'dropped' }
        }
        $entries += @{
            SIMKL_ID = $mov.movie.ids.simkl
            Title = $mov.movie.title
            Type = 'movie'
            Year = If (!($mov.movie.year)) { "0" } Else { $mov.movie.year }
            Watchlist = $movStatus
            LastEpWatched = ''
            WatchedDate = $mov.last_watched_at
            Rating = If (!($mov.user_rating)) { "" } Else { $mov.user_rating }
            Memo = ''
            TVDB = If (!($mov.movie.ids.tvdb)) { "" } Else { $mov.movie.ids.tvdb }
            TMDB = If (!($mov.movie.ids.tmdb)) { "" } Else { $mov.movie.ids.tmdb }
            IMDB = If (!($mov.movie.ids.imdb)) { "" } Else { $mov.movie.ids.imdb }
        }
    }

    ForEach ($show in $simklJson.shows) {
        Write-Host "Converting show: [$($show.show.ids.simkl)] $($show.show.title)"
        $tvStatus = Switch ($show.status) {
            'completed' { 'completed' }
            'hold' { 'on hold' }
            'watching' { 'watching' }
            'plantowatch' { 'plan to watch' }
            'notinteresting' { 'dropped' }
        }
        $entries += @{
            SIMKL_ID = $show.show.ids.simkl
            Title = $show.show.title
            Type = 'tv show'
            Year = If (!($show.show.year)) { "0" } Else  { $show.show.year }
            Watchlist = $tvStatus
            LastEpWatched = If (!($show.last_watched)) { "" } Else { $show.last_watched.ToLower() }
            WatchedDate = $show.last_watched_at
            Rating = If (!($show.user_rating)) { "" } Else { $show.user_rating }
            Memo = ''
            TVDB = If (!($show.show.ids.tvdb)) { "" } Else { $show.show.ids.tvdb }
            TMDB = If (!($show.show.ids.tmdb)) { "" } Else { $show.show.ids.tmdb }
            IMDB = If (!($show.show.ids.imdb)) { "" } Else { $show.show.ids.imdb }
        }
    }

    $malCurrent = 0; $malPtw = 0; $malPause = 0; $malDrop = 0; $malFinish = 0; $unlistedEntries = ""; $aniCount = 0
    ForEach ($anime in $simklJson.anime) {
        Write-Host "Converting anime: [$($anime.show.ids.simkl)] $($anime.show.title)"
        $aniCount++
        Switch ($anime.status) {
            'completed' {
                $malStatus = 'Completed'
                $aniStatus = $malStatus.ToLower()
                $malFinish++
            }
            'hold' {
                $malStatus = 'On-Hold'
                $aniStatus = 'on hold'
                $malPause++
            }
            'watching' {
                $malStatus = 'Watching'
                $aniStatus = $malStatus.ToLower()
                $malCurrent++
            }
            'plantowatch' {
                $malStatus = 'Plan to Watch'
                $aniStatus = $malStatus.ToLower()
                $malPtw++
            }
            'notinteresting' {
                $malStatus = 'Dropped'
                $aniStatus = $malStatus.ToLower()
                $malDrop++
            }
        }
        $entries += @{
            SIMKL_ID = $anime.show.ids.simkl
            Title = $anime.show.title
            Type = 'anime'
            Year = If (!($anime.show.year)) {"0"} Else { $anime.show.year }
            Watchlist = $aniStatus
            LastEpWatched = If (!($anime.last_watched)) {""} Else { "s1" + $anime.last_watched.ToLower() }
            WatchedDate = If (!($anime.last_watched_at)) {""} Else { $anime.last_watched_at }
            Rating = If (!($anime.user_rating)) {""} Else { $anime.user_rating }
            Memo = ''
            TVDB = If (!($anime.show.ids.tvdb)) {""} Else { $anime.show.ids.tvdb }
            TMDB = If (!($anime.show.ids.tmdb)) {""} Else { $anime.show.ids.tmdb }
            IMDB = If (!($anime.show.ids.imdb)) {""} Else { $anime.show.ids.imdb }
        }

        $xmlCommonEntry = @"
<series_title><![CDATA[$($anime.show.title)]]></series_title>
        <series_episodes>$($anime.total_episodes_count)</series_episodes>
        <my_watched_episodes>$(If (!($anime.last_watched)) { "0" } Else{$anime.last_watched.Replace('E','')})</my_watched_episodes>
        <my_score>$(If (!($anime.user_rating)) {"0"} Else { $anime.user_rating })</my_score>
        <my_status>$($malStatus)</my_status>
        <my_start_date>0000-00-00</my_start_date>
        <my_finish_date>0000-00-00</my_finish_date>
        <update_on_import>1</update_on_import>
"@

        If ($Null -ne $anime.show.ids.mal) {
            $xmlEntries += @"
`n    <anime>
        <series_animedb_id>$($anime.show.ids.mal)</series_animedb_id>
        <!--simkl_animedb_id>$($anime.show.ids.simkl)</simkl_animedb_id-->
        $($xmlCommonEntry)
    </anime>
"@
        } Else {
            $unlistedEntries += @"
`n        - [$($anime.show.ids.simkl)] $($anime.show.title)
"@
            $xmlEntries += @"
`n    <!--anime>
        <simkl_animedb_id>$($anime.show.ids.simkl)</simkl_animedb_id>
        $($xmlCommonEntry)
    </anime-->
"@
        }
    }

    # Convert to CSV
    # Utilize ConvertTo-Json | ConvertFrom-Json to sanitize unwanted errors...
    #    when converting directly from hashtable to CSV
    Write-None
    Write-Host "Exporting SIMKL watchlist to CSV"
    $entries | ConvertTo-Json | ConvertFrom-Json | Export-Csv -Path ./simkl/SimklBackup.csv -Encoding utf8 -Force -NoTypeInformation -UseQuotes AsNeeded

    Write-None
    Write-Host "Exporting SIMKL watchlist to MAL-XML"
    $xmlData = @"
<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
    <myinfo>
        <user_id></user_id>
        <user_export_type>1</user_export_type>
        <user_total_anime>$($malCurrent + $malPtw + $malFinish + $malPause + $malDrop)</user_total_anime>
        <!--user_total_simkl_anime>$($aniCount)</user_total_simkl_anime-->
        <user_total_plantowatch>$($malPtw)</user_total_plantowatch>
        <user_total_watching>$($malCurrent)</user_total_watching>
        <user_total_completed>$($malFinish)</user_total_completed>
        <user_total_onhold>$($malPause)</user_total_onhold>
        <user_total_dropped>$($malDrop)</user_total_dropped>
    </myinfo>

    <!--
        Created by GitHub:nattadasu/animeManga-autoBackup
        Exported at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $((Get-TimeZone).Id)
    -->

    <!--Unindexed Entry on MAL
        Format:
        - [SIMKL ID] Title
        ========================================$($unlistedEntries)
    -->

"@
    $xmlData += $xmlEntries
    $xmlData += "`n</myanimelist>"

    $xmlData | Out-File -Path ./simkl/animeList.xml -Encoding utf8 -Force

    $readMe = @"
This folder contains your SIMKL backup in various formats.

* animeList.xml     : MAL-compatible XML format. Use this if you want strictly import only anime list.
* data.json         : JSON file fetched directly from SIMKL server.
* SimklBackup.csv   : CSV file format, suitable for importing the list to 3rd party.
* SimklBackup.zip   : contains JSON file od data.json. This format is expected to be used for reimporting list to SIMKL only.
"@

    #Remove legacy README file name
    If (Test-Path -Path ./simkl/README -ErrorAction SilentlyContinue) {
        Remove-Item -Path ./simkl/README
    }
    $readMe | Out-File -Path ./simkl/README.txt -Encoding utf8 -Force
}

Function Get-TraktBackup {
    Add-Directory -Path ./trakt -Name Trakt

    $traktUsername = $Env:TRAKT_USERNAME

    Write-None
    Write-Host "Exporting Trakt.tv data"
    # Code is based on https://github.com/seanbreckenridge/traktexport/blob/master/traktexport/__init__.py

    <# If (Get-Command -Name "traktexport" -ErrorAction SilentlyContinue) {
        Write-Host "Trakt Exporter Python Module is installed"
    } Else {
        Write-Host "Installing Trakt Exporter Python Module"
        pip install traktexport
    } #>

    Write-Host "Configuring config file"

    $traktExportJson = "{`"CLIENT_ID`": `"$($Env:TRAKT_CLIENT_ID)`", `"CLIENT_SECRET`": `"$($Env:TRAKT_CLIENT_SECRET)`", `"OAUTH_TOKEN`": `"$($Env:TRAKT_OAUTH_TOKEN)`", `"OAUTH_REFRESH`": `"$($Env:TRAKT_OAUTH_REFRESH)`", `"OAUTH_EXPIRES_AT`": $($Env:TRAKT_OAUTH_EXPIRY)}"

    # Check if linux or windows
    If ($Env:XDG_DATA_HOME) {
        $dataDir = $Env:XDG_DATA_HOME
    } ElseIf ($isWindows) {
        $dataDir = "~/.traktexport"
    } Else {
        $dataDir = "~/.local/share"
    }

    # Check if file exist
    If (Test-Path -Path "$dataDir/traktexport.json" -PathType Leaf) {
        Write-Host "Config file exists" -ForegroundColor Green
    } Else {
        Write-Host "Config file does not exist" -ForegroundColor Red
        Write-Host "Creating config file" -ForegroundColor Yellow
        New-Item -Path "$dataDir/traktexport.json" -Force -ItemType File -Value $traktExportJson
    }

    traktexport export $traktUsername | Out-File "./trakt/data.json"
}

Function Get-VNDBBackup {
    Write-None
    Write-Host "Checking if curl is installed as fallback due to Invoke-WebRequest not working properly in handling cookies"
    Test-Binary -Binary curl

    Add-Directory -Path ./vndb -Name VNDB

    Write-None
    Write-Host "Exporting VNDB game list"
    $vndbUid = $Env:VNDB_UID
    $vndbAuth = $Env:VNDB_AUTH
    $vndbUrl = "https://vndb.org/$($vndbUid)/list-export/xml"

    curl -o ./vndb/gameList.xml  -X GET --cookie "vndb_auth=$($vndbAuth)" -A $userAgent $vndbUrl
}

# Skip if User Agent variable is not set when user filled ANIMEPLANET_USERNAME, MANGAUPDATES_SESSION, MAL_USERNAME, SHIKIMORI_KAWAI_SESSION, or VNDB_UID
If (($Env:ANIMEPLANET_USERNAME) -or ($Env:MANGAUPDATES_SESSION) -or ($Env:MANGAUPDATES_SESSION) -or ($Env:SHIKIMORI_KAWAI_SESSION) -or ($Env:VNDB_UID)) {
    Confirm-UserAgent
}

$userAgent = $Env:USER_AGENT

# Check each Environment Variable if filled, if not skip
If ($Env:ANILIST_USERNAME) { Get-AniListBackup }
If ($Env:ANIMEPLANET_USERNAME) { Get-AnimePlanetBackup }
If ($Env:ANNICT_PERSONAL_ACCESS_TOKEN) { Get-AnnictBackup }
If ($Env:KITSU_EMAIL) { Get-KitsuBackup }
If ($Env:MANGAUPDATES_SESSION) { Get-MangaUpdatesBackup }
If ($Env:MANGADEX_USERNAME) { Get-MangaDexBackup }
If ($Env:MAL_USERNAME) { Get-MyAnimeListBackup }
If ($Env:NOTIFYMOE_NICKNAME) { Get-NotifyMoeBackup }
If ($Env:SHIKIMORI_KAWAI_SESSION) { Get-ShikimoriBackup }
If ($Env:SIMKL_CLIENT_ID) { Get-SimklBackup }
If ($Env:TRAKT_USERNAME) { Get-TraktBackup }
If ($Env:VNDB_UID) { Get-VNDBBackup }

Write-None
Write-Host "Format JSON files"
Get-ChildItem -Path "*" -Filter "*.json" -File  -Recurse | ForEach-Object {
    Write-Host "Formatting $($_)"
    Format-Json -Json (Get-Content $_ -Raw).trim() -Indentation 2 -ErrorAction SilentlyContinue | Out-File -FilePath $_
}
