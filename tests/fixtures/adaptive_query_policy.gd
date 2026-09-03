## Test policy only: start at five; reduce to two, then one after transient errors.
extends RefCounted
var limit:=5
var cooldown_until:=0
var transient_errors:=0
var retries:=0
var stopped:=false
var reductions:=0
func failure(status: int, attempt: int, now_ms: int) -> bool:
	if status in [401,403,429]:
		stopped=true
		return false
	if not (status==0 or status==408 or status>=500): return false
	transient_errors+=1
	var next_limit:=2 if limit==5 else 1
	if next_limit<limit: reductions+=1
	limit=next_limit
	cooldown_until=maxi(cooldown_until,now_ms+(2000 if attempt==1 else 4000))
	if transient_errors>=8:
		stopped=true
		return false
	if attempt>=3: return false
	retries+=1
	return true
