using namespace System.Security.Cryptography.X509Certificates;

$curl       = 'c:\cygwin64\bin\curl.exe'
$baseUrlApi = 'https://foundation-dev-api.symphony.com'
$baseUrl    = 'https://foundation-dev.symphony.com'

function New-Session {
	param(
		$password = $global:password,
		$certPath = $global:certPath,
		$keyPath  = $global:keyPath
	)
		
	Write-Debug "Fetching session token."
	$sessionToken = ConvertFrom-Json (& $curl -X POST  --cert "$($certPath):$password"  --key $keyPath "$baseUrlApi/sessionauth/v1/authenticate"  -H "cache-control: no-cache" 2> $null)
	Write-Debug "Session token is $sessionToken"
	Write-Debug "Fetching key token."
	$keyManagerToken  = ConvertFrom-Json (& $curl -X POST --cert "$($certPath):$password"  --key $keyPath "$baseUrlApi/keyauth/v1/authenticate"  -H "cache-control: no-cache" 2> $null)
	Write-Debug "Key token is $keyToken"
	
	$session = @{
		sessionToken=$sessionToken.token
		keyManagerToken = $keyManagerToken.token
		certPath = $certPath
		keyPath = $keyPath
		password = $password
	}
	
	$global:LastSession = $session
	$session
}

function Get-Stream {
	param (
		$session=$global:LastSession
	)
	
	$array = ConvertFrom-Json (& $curl -X POST "$baseUrl/pod/v1/streams/list" --cert "$($session.certPath):$($session.password)"  --key $session.keyPath -H "sessionToken: $($session.sessionToken)" 2>$null )
	foreach ($item in $array) {
		$item
	}
}

function Get-Message {
	param (
		$session=$global:LastSession,		
		[parameter(ValueFromPipeline=$true)]	
		$stream,
		[Parameter(Mandatory=$true)]
		[datetime]$Since
	)	
	
	begin {		
		$timeT = ($Since | ConvertTo-TimeT )
	}
	process {
		$safeStreamId = Get-SafeStreamId $stream
		Write-Debug "$baseUrl/agent/v4/stream/$safeStreamId/message?since=$timeT"
		$array = ConvertFrom-Json (& $curl -X GET "$baseUrl/agent/v4/stream/$safeStreamId/message?since=$timeT" --cert "$($session.certPath):$($session.password)"  --key $session.keyPath -H "sessionToken: $($session.sessionToken)" -H "keyManagerToken: $($session.keyManagerToken)" 2>$null )
		
		foreach ($item in $array) {
			$tagList = ([xml]$item.message).selectNodes('//span')."#text"
			$item | Add-Member -MemberType NoteProperty -Name Tags -value $tagList
			$item.Timestamp = ConvertFrom-TimeT $item.timestamp
			$item
		}
	}
}

function ConvertFrom-TimeT {
	param(
		[parameter(ValueFromPipeline)]	
		$date
	)
	([DateTime]::new(1970, 1, 1)).AddMilliseconds($date)
}

function ConvertTo-TimeT {
	param(
		[parameter(ValueFromPipeline)]	
		$date
	)
	($date - [DateTime]::new(1970, 1, 1)).TotalMilliSeconds
}

function Get-SafeStreamId {
	param(
		$stream
	)
	
	if ( $stream -is [string]) {
		$streamId = $stream		
	} else {
		$streamId = $stream.id
	}
		
	$streamId -replace '/', '_' -replace '==$', '' -replace '=', '' -replace '\+', '-'	
}

function Send-Message {
	param (
		[Parameter(Mandatory=$true)]
		$stream,
		$session=$global:LastSession,
		[parameter(ValueFromPipeline)]
		$message = ""
	)
	
	Process {	
		$safeStreamId = Get-SafeStreamId $stream
		ConvertFrom-Json (& $curl -X POST "$baseUrl/agent/v4/stream/$safeStreamId/message/create" --cert "$($session.certPath):$($session.password)"  --key $session.keyPath -H "Content-Type: multipart/form-data" -H "sessionToken: $($session.sessionToken)" -H "keyManagerToken: $($session.keyManagerToken)"  --form-string "message=<messageML>$message</messageML>" 2>$null)
	}
	
}

Export-ModuleMember Send-Message
Export-ModuleMember New-Session
Export-ModuleMember Get-Stream
Export-ModuleMember Get-Message


