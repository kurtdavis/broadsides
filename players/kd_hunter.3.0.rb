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
$perfect       = false
$hShots        = Hash.new(0)


# Extend String to have 'pred' method similar to succ.
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
#$fhLog.puts "\t\t#{col} - #{row}\n"
          #top / bottom / right / left
          targets.push(col + row.pred) if (row != "1"   && $hShots[col + row.pred] == 0)
          targets.push(col + row.succ) if (row != "10"  && $hShots[col + row.succ] == 0)
          targets.push(col.pred + row) if (col != "A"   && $hShots[col.pred + row] == 0)
          targets.push(col.succ + row) if (col != "J"   && $hShots[col.succ + row] == 0)
#$fhLog.puts "\t\t#{targets.size}\n"
        }
      }
    end
    $fhLog.puts "\ttargets1 : #{targets.join(', ')}\n"
    #$fhLog.puts "\taSavedTargets1 : #{$aSavedTargets.join(', ')}\n"
    # Add our saved targets from previous rounds...
    targets = targets | $aSavedTargets
    #$fhLog.puts "\ttargets2 : #{targets.join(', ')}\n"
    $aSavedTargets = []
    $aLastHits = []

    # Remove any targets over the iNumShots allowed... save those for later.
    $aSavedTargets = targets.slice!(-(targets.size - iNumShots) .. -1) if (targets.size > iNumShots)

    # Remove any caculated targets from the shots avaliable.
    #$fhLog.puts "\ttargets4 : #{targets.join(', ')}\n"
    #$fhLog.puts "\tAvalTargets1 : #{$aAvalTargets.join('.')}\n"
    $aAvalTargets = $aAvalTargets - targets
    #$fhLog.puts "\ttargets5 : #{targets.join(', ')}\n"
    #$fhLog.puts "\tAvalTargets2 : #{$aAvalTargets.join('.')}\n"

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
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"

  when /\AACTION SHOTS (\d)/
    # Get the shots to take...
    sShots = "SHOTS #{getTargets($1.to_i).join(' ')}"
    puts "#{sShots}"
    $fhLog.puts "#{sShots}"
  
  when /\AACTION FINISH\b/
    # Show all our shots here...
    $hShots.each_key { |target|
      $fhLog.puts "#{target} shot -> #{$hShots[target]}" if $hShots[target] > 0
    }
    # We don't save data, so we just need to tell the server we are done:
    puts "FINISH"
    while (DATA.gets) do
      #eval($_)
    end
    $fhLog.close

  # Obviously, you will also want to deal with INFO messages here...
  when /\AINFO SHOTS kd_hunter (.*)\b/
    counter = 0
    $1.scan(/(\w\d+):(\w+)\b/) {
      if ($2 == 'hit')
        $fhLog.puts "  HIT! #{$opponet}:#{$1}"
        $aLastHits.push($1)
        counter += 1
        # Now we want to shoot all around this HIT until no more hits returned.
      end
    }
    $perfect = (counter == 6)
  when /\AINFO SETUP players:(\w+),(\w+) board:(\d+)x(\d+) ships:(.*)\b/
	$opponet = ($1 == 'kd_hunter') ? $2 : $1
	# This list of all possible shots will be fired at in order
	# Complete Random board...
	#$aAvalTargets = (1..10).map { |y| ("A".."J").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	#$aAvalTargets = ['B2','C3','I2','H3','B9','C8','I9','H8'] | $aAvalTargets # Pattern prepended...not so good an idea
	# Random Quadrents...
	$aAvalTargets1 = (1..5).map { |y| ("A".."E").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	$aAvalTargets2 = (1..5).map { |y| ("F".."J").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	$aAvalTargets3 = (6..10).map { |y| ("A".."E").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	$aAvalTargets4 = (6..10).map { |y| ("F".."J").map { |x| "#{x}#{y}" } }.flatten.sort_by { rand }
	$aAvalTargets  = (0..24).map { |i| [$aAvalTargets1[i], $aAvalTargets2[i], $aAvalTargets3[i], $aAvalTargets4[i]] }.flatten
	# Create hash to track shots...
	$aAvalTargets.each { |key| $hShots[key] = 0 }
	
	# Create logger
	$fhLog = File.open("kd_hunter.txt", File::RDWR|File::CREAT)
	# Get all the previous hits for this player...
	nsaPlayerProfiler($opponet, $fhLog)
	#$fhLog.close
	#$fhLog = File.open("kd_hunter.txt", "a")
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
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
    puts "SHIPS 5:C9:H 4:A5:V 3:E2:H 3:G5:H 2:D6:H"
__END__
# DO NOT REMOVE THE PRECEEDING LINE.
# Everything else in this file will be ignored.
