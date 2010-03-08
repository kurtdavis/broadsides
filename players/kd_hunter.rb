# 
# This line, required by the rules, ensures the server sees our responses as
# soon as they are written.
# 
$stdout.sync = true

# Some global vars..
$aAvalTargets  = []
$aLastHits     = []
$aSavedTargets = []
$opponet       = ""
$iTurn         = 0
$perfect       = false
$hShots        = Hash.new(0)
$hHits         = Hash.new(0)
$sResult       = ""


# Extend String to have 'pred' method similar to 'succ' but opposite.
class String
  def pred
    match=false
    if /[0-9A-Za-z]/.match(self)
      preds = [ [/[1-9B-Zb-z](?:[^0-9A-Za-z]|[0Aa])*$/, # borrow
                 proc { |m|
                   match=true
                   m.tr('a-zA-Z0-9', 'za-yZA-Y90-8')
                 }],
                [/^([^0Aa]*)([Aa])(\2.*)$/, # eg aaA0 -> zZ9
                 proc { |m|
                   match=true
                   $1 + $3.tr('a-zA-Z0-9', 'za-yZA-Y90-8')
                 }],
                [/^([^0-9A-Za-z]*)([0Aa])$/,
                 proc { |m|
                   match=true
                   m[-1] -= 1
                   m
                 }]
              ]
      preds.each { |re, repl|
        new_str = self.sub(re, &repl)
        return new_str if match
      }   
    end
    return nil
  end
  def pred!
    new_str = pred
    self.replace(new_str) unless new_str.nil?
    return self
  end
end


def initShips ()
	aLines = []
	bGrab = false
	while (DATA.gets) do
		if ($_ =~ /::SHIPS::/)
			bGrab = !bGrab
			next
		end
		next if !bGrab

		aShips = eval($_)
		aLines.push(aShips) 
	end
	aShips =  ['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
	aLines = aLines.uniq.sort_by { rand }
	return aLines[2]
end

def initTargets (aTargetsPrepend, aTargetsAppend)
	# Create list of all possible shots to be fired in array's order
	
	aAvalTargets = []
	stShotsTaken = {}
	# Complete Random board... too random: [disabled]
	#aAvalTargets = (1..10).map { |y| ("A".."J").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }

	# Pattern prepended...not so good an idea: [disabled]
	#aAvalTargets = ['B2','C3','I2','H3','B9','C8','I9','H8'] | aAvalTargets 

	# Random by Quadrents... eh?:
	aAvalTargets1 = (1..5).map { |y| ("A".."E").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	aAvalTargets2 = (1..5).map { |y| ("F".."J").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	aAvalTargets3 = (6..10).map { |y| ("A".."E").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	aAvalTargets4 = (6..10).map { |y| ("F".."J").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	aAvalTargets  = (0..24).map { |i| [aAvalTargets1[i], aAvalTargets2[i], aAvalTargets3[i], aAvalTargets4[i]] }.flatten
	# Initialize our hash to track shots as well:
	aAvalTargets.each { |key| stShotsTaken[key] = 0 }
	# Now perform prepend/append actions:
	aAvalTargets = aTargetsPrepend | aAvalTargets if aTargetsPrepend.size > 0
	aAvalTargets = aAvalTargets - aTargetsAppend  if aTargetsAppend.size > 0
	aAvalTargets = aAvalTargets + aTargetsAppend  if aTargetsAppend.size > 0
	return aAvalTargets, stShotsTaken
end

def nsaPlayerProfiler (opponet, fhLog)
	# Get all the previous hits for this player...
	# and stick them at front of our array. (bad if they moved.)
	aHits = []
	fhLog.readlines.each { |line|
		line.chomp!
		if (line =~ /HIT! #{opponet}:(\w\d)/)
			aHits.push($1)
		end
	}
	if aHits.size > 0
		aHits = aHits.reverse.uniq.sort_by { rand }
		$aAvalTargets = $aAvalTargets - aHits
		$aAvalTargets = aHits + $aAvalTargets
	end
end
 
def getTargets (iNumShots)
    targets = []
    if ($aLastHits.size > 0 && !$perfect)
	$aLastHits.each { |hit|
		#Get the row/column and try up to four around it.
		hit.scan(/(\w)(\d)/) {
		  col = $1
		  row = $2
		  #top / bottom / right / left
		  targets.push(col + row.pred) if (row != "1"   && $hShots[col + row.pred] == 0)
		  targets.push(col + row.succ) if (row != "10"  && $hShots[col + row.succ] == 0)
		  targets.push(col.pred + row) if (col != "A"   && $hShots[col.pred + row] == 0)
		  targets.push(col.succ + row) if (col != "J"   && $hShots[col.succ + row] == 0)
		}
	}
	$aLastHits = []
    end
	# Add our saved targets from previous rounds...
	targets = targets | $aSavedTargets
	#$fhLog.puts "\ttargets2 : #{targets.join(', ')}\n"
	$aSavedTargets = []
    #$fhLog.puts "\ttargets1 : #{targets.join(', ')}\n"

    # Remove any targets over the iNumShots allowed... save those for later.
    $aSavedTargets = targets.slice!(-(targets.size - iNumShots) .. -1) if (targets.size > iNumShots)

    # Remove any caculated targets from the shots avaliable.
    $aAvalTargets = $aAvalTargets - targets

    # Pad more targets if needed.
    if (targets.size < iNumShots)
      targets = targets + (1..(iNumShots - targets.size)).map {
        target = $aAvalTargets.shift 
        $fhLog.puts "\t----#{target}\n"
        target
      }
      # In case we run out of targets and need more shots for final round.
      if (targets.size < iNumShots)
        targets = targets + (1..(iNumShots - targets.size)).map {'A1'}
      end 
    end 
    $fhLog.puts "\tiNumShots : #{iNumShots}\n"
    $fhLog.puts "\taLastHits : #{$aLastHits.join(', ')}\n"
    $fhLog.puts "\taSavedTargets : #{$aSavedTargets.join(', ')}\n"
    $fhLog.puts "\ttargets : #{targets.join(', ')}\n"
    # Increment our shots taken here.
    targets.each { |cell| $hShots[cell] += 1 }

    return targets
end
# This loop reads messages from the server, one line at a time.
ARGF.each_line do |line|
  case line
  when /\AACTION SHIPS\b/
	# We have been asked to place our ships, so we send a valid response:
	puts "SHIPS #{initShips().join(' ')}"

  when /\AACTION SHOTS (\d)/
    # Get the shots to take...
    sShots = "SHOTS #{getTargets($1.to_i).join(' ')}"
    puts "#{sShots}"
    $fhLog.puts "#{sShots}"
  
  when /\AACTION FINISH\b/
	# Show all our shots here...
	$hShots.each_key { |target|
		$fhLog.puts "#{target} shot -> #{$hShots[target]}" if $hShots[target] > 1
	}
	$fhLog.puts " ==== turns to #{$sResult}  -- #{$iTurn} -- ==== \n"
	$fhLog.close
	# DONE!
	puts "FINISH"

  # Obviously, you will also want to deal with INFO messages here...
  when /\AINFO SHOTS kd_hunter (.*)\b/
    counter = 0
    $1.scan(/(\w\d+):(\w+)\b/) {
      if ($2 == 'hit')
        $fhLog.puts "  HIT! #{$opponet}:#{$1}"
        $aLastHits.push($1)
	$hHits[$1] = $iTurn
        counter += 1
        # Now we want to shoot all around this HIT until no more hits returned.
      end
    }
    $iTurn += 1
    $perfect = (counter == 6)
  when /\AINFO SETUP players:(\w+),(\w+) board:(\d+)x(\d+) ships:(.*)\b/
	$opponet = ($1 == 'kd_hunter') ? $2 : $1
	($aAvalTargets, $hShots) = initTargets([],[])
	
	# Create logger
	$fhLog = File.open("kd_hunter.txt", File::RDWR|File::CREAT)
	# Get all the previous hits for this player...
	nsaPlayerProfiler($opponet, $fhLog)
	#$fhLog.close
	#$fhLog = File.open("kd_hunter.txt", "a")
  when /\AINFO WINNER (\w+)\b/
	$sResult = ($1 == "kd_hunter") ? "win" : "lose"
  else
    #$fhLog.puts "???: #{line}"
  end
end




__END__
# get info about the script (size, date of last modification)
kilosize = DATA.stat.size / 1024
last_modif = DATA.stat.mtime
$fhLog.puts "<P>Script size is #{kilosize}"
$fhLog.puts "<P>Last script update: #{last_modif}"
::SHIPS::
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:I3:V', '4:B5:V', '3:D1:H', '3:F4:H', '2:D6:H']
['5:D2:V', '4:J5:V', '3:E2:H', '3:G8:V', '2:D8:V']
::SHIPS::
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
['5:C9:H', '4:A5:V', '3:E2:H', '3:G5:H', '2:D6:H']
__END__
# DO NOT REMOVE THE PRECEEDING LINE.
# Everything else in this file will be ignored.
