gh release view --json assets 2>/dev/null | python3 -mjson.tool | sed  '1,2d;$d' | json -ga name url size -d, | sort | grep Uefi| (
while read -r line; do
	name=$(echo $line | cut -d"," -f1 | awk '{print tolower($0)}')
	url=$(echo $line | cut -d"," -f2)
	if [ "${name: -3}" == ".xz" ]; then
             echo  "$url"
	fi
done
)
