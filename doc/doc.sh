#/bin/bash

clear

script_dir="$(dirname "$0")"

# Load The Bash procedure Objects
json_file="$script_dir/in/features.json"
json_data=$(cat "$json_file")


bash_ass_aray(){
    # Get all the outer keys (categories or features)
    keys=$(echo "$json_data" | jq -r 'keys[]')
   
    # Loop over each key
    for key in $keys; do

        echo "# $key"
        
        # Get all the inner keys (like BUILD_ONLY)
        inner_keys=$(echo "$json_data" | jq -r ".$key | keys[]")
        
        # Loop over each inner key
        for inner_key in $inner_keys; do
            # Assign the values to variables
            author=$(echo "$json_data" | jq -r ".$key.$inner_key.Author")
            src_reference=$(echo "$json_data" | jq -r ".$key.$inner_key.src_reference")
            desc=$(echo "$json_data" | jq -r ".$key.$inner_key.desc")
            example=$(echo "$json_data" | jq -r ".$key.$inner_key.\"example / [note] test case\"")
            status=$(echo "$json_data" | jq -r ".$key.$inner_key.status")
            doc_link=$(echo "$json_data" | jq -r ".$key.$inner_key.doc_link")

            cat << EOF 

    ["id,$inner_key"]="$inner_key"
    ["author,$inner_key"]="$author"
    ["src_reference,$inner_key"]="$src_reference"
    ["desc,$inner_key"]="$desc"
    ["example,$inner_key"]="$example"
    ["status,$inner_key"]="$status"
    ["doc_link,$inner_key"]="$doc_link"

EOF
        done
    done
}

markdown_table(){
    # Get all the outer keys (categories or features)
    keys=$(echo "$json_data" | jq -r 'keys[]')
   
    # Loop over each key
    for key in $keys; do

        echo "# $key"
        cat << EOF

| Feature |  desc | example | src_reference | status |
| :-----: | :---: | :---: | :-----: | :---------: |
EOF
        # Get all the inner keys (like BUILD_ONLY)
        inner_keys=$(echo "$json_data" | jq -r ".$key | keys[]")
        
        # Loop over each inner key

    for inner_key in $inner_keys; do
        # Assign the values to variables
        author=$(echo "$json_data" | jq -r ".$key.$inner_key.Author")
        src_reference=$(echo "$json_data" | jq -r ".$key.$inner_key.src_reference")
        desc=$(echo "$json_data" | jq -r ".$key.$inner_key.desc")
        example=$(echo "$json_data" | jq -r ".$key.$inner_key.\"example / [note] test case\"")
        status=$(echo "$json_data" | jq -r ".$key.$inner_key.status")
        doc_link=$(echo "$json_data" | jq -r ".$key.$inner_key.doc_link")
    cat << EOF 
| $inner_key | $desc | $example | [references]($src_reference) |  $status | 
EOF


    done
done
}

cat << EOF
Hold on to your hat, we're about to sort out the formatting. 
Just need a Big Gulp of Pepsi to get the job done.

Us old-timers might be using the bash shell, and yes, that does mean we're a bit slow. 

We're going to create a bash associative array and a markdown table from the JSON file.

EOF

# Create the bash Array script
echo "#!/bin/bash"  > "$script_dir/out/features.sh"

cat << EOF
Keep that JSON file as simple as a Sunday morning for now. 
We can spice it up with some fancy nesting later if we're feeling adventurous.

And remember, patience is a virtue. So sit back, relax, and let the science happen.

EOF


bash_ass_aray >> "$script_dir/out/features.sh"
clear

cat << EOF
Alrighty, we've got our associative array all set. 
Now, let's whittle out a table for markdown. Patience is key here, remember we're more tortoise than hare.

EOF

markdown_table > "$script_dir/out/features.md"

cat << EOF
Whew! That was a bit of a slow ride, but we made it. 
Not too painful, we hope. Thanks for moseying down this path with us. 
Remember, slow and steady not only wins the race, but also ensures stability. 


EOF


