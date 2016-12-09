

name 'VolumeFinder'
rs_ca_ver 20160622
short_description "Finds unattached volumes"

#Copyright 2016 RightScale
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

#RightScale Cloud Application Template (CAT)

# DESCRIPTION
# Find unattached volumes and takes an action (alert, alert + delete)
#
# FEATURES
# Users can automatically have unattached volumes deleted.
#



##################
# User inputs    #
##################
parameter "param_action" do
  category "Volume"
  label "Volume Action"
  type "string"
  allowed_values "ALERT", "ALERT AND DELETE"
  default "ALERT"
end

parameter "param_email" do
  category "Contact"
  label "email address (reports are sent to this address)"
  type "string"
end

parameter "param_days_old" do
  category "Volume"
  label "Report on volumes that are these many days old"
  allowed_values "1", "7", "30"
  type "number"
  default "30"
end


##################
# Operations     #
##################

operation "launch" do
  description "Find unattached volumes"
  definition "launch"
end


##################
# Definitions    #
##################

define launch($param_email,$param_action,$param_days_old) return $param_email,$param_action,$param_days_old do
        call find_unattached_volumes($param_action)
        sleep(20)
        call send_email_mailgun($param_email)
end


define find_unattached_volumes($param_action) do

    #get all volumes
    @all_volumes = rs_cm.volumes.index(view: "default")

    #search the collection for only volumes with status = available
    @volumes_not_in_use = select(@all_volumes, { "status": "available" })
    #@@not_attached = select(@all_volumes, { "created_at": "available" })

    $header="\<\!DOCTYPE html PUBLIC \"-\/\/W3C\/\/DTD XHTML 1.0 Transitional\/\/EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\"\>
    <html xmlns=\"http:\/\/www.w3.org\/1999\/xhtml\">
        <head>
            <meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />
            <title></title>
            <style></style>
        </head>
        <body>
          <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" height=\"100%\" width=\"100%\" id=\"bodyTable\">
              <tr>
                  <td align=\"center\" valign=\"top\">
                      <table border=\"0\" cellpadding=\"20\" cellspacing=\"0\" width=\"100%\" id=\"emailContainer\">
                          <tr>
                              <td align=\"center\" valign=\"top\">
                                  <table border=\"0\" cellpadding=\"20\" cellspacing=\"0\" width=\"100%\" id=\"emailHeader\">
                                      <tr>
                                          <td align=\"center\" valign=\"top\">
                                              We found the following unattached volumes
                                          </td>

                                      </tr>
                                  </table>
                              </td>
                          </tr>
                          <tr>
                              <td align=\"center\" valign=\"top\">
                                  <table border=\"0\" cellpadding=\"10\" cellspacing=\"0\" width=\"100%\" id=\"emailBody\">
                                      <tr>
                                          <td align=\"center\" valign=\"top\">
                                              Volume Name
                                          </td>
                                          <td align=\"center\" valign=\"top\">
                                              Volume Size
                                          </td>
                                          <td align=\"center\" valign=\"top\">
                                              Volume Href
                                          </td>
                                          <td align=\"center\" valign=\"top\">
                                              Volume Owner
                                          </td>
                                          <td align=\"center\" valign=\"top\">
                                              Volume ID
                                          </td>
                                      </tr>
                                      <tr>"
      $list_of_volumes=""
      $table_start="<td align=\"center\" valign=\"top\">"
      $table_end="</td>"
      #refactor.
      if $param_action == "ALERT AND DELETE"
        #insert($list_of_volumes, 0, "The following unattached volumes were found and deleted:%0D ")
      else
      #  insert($list_of_volumes, 0, "The following unattached volumes were found:%0D ")
      end

      #/60/60/24
      $curr_time = now()
      #$$day_old = now() - (60*60*24)

      foreach @volume in @volumes_not_in_use do
        $$error_msg=""
        #convert string to datetime to compare datetime
        $volume_created_at = to_d(@volume.updated_at)

        #the difference between dates
        $difference = $curr_time - $volume_created_at

        #convert the difference to days
        $how_old = $difference /60/60/24


        #check for Azure specific images that report as "available" but should not
        #be reported on or deleted.
        if @volume.resource_uid =~ "@system@Microsoft.Compute/Images/vhds"
          #do nothing.

        #check the age of the volume
        elsif $param_days_old < $how_old
          $volume_name = @volume.name
          $volume_size = @volume.size
          $volume_href = @volume.href
          $volume_id   = @volume.resource_uid
            #here we decide if we should delete the volume
            if $param_action == "ALERT AND DELETE"
              sub task_name: "Delete Volume" do
                task_label("Delete Volume")
                sub on_error: handle_error() do
                  @volume.destroy()
                end
              end
            end

        $volume_table = $table_start + $volume_name + $table_end + $table_start + $volume_size + $table_end + $table_start + $volume_href + $table_end + $table_start + "edwin@rightscale.com" + $table_end + $table_start + $volume_id + $table_end
            insert($list_of_volumes, -1, $volume_table)
        end

      end

          $footer="</tr>
      </table>
  </td>
</tr>
<tr>
  <td align=\"center\" valign=\"top\">
      <table border=\"0\" cellpadding=\"20\" cellspacing=\"0\" width=\"100%\" id=\"emailFooter\">
          <tr>
              <td align=\"center\" valign=\"top\">
                  This report was generated by a policy cloud application template (RightScale)
              </td>
          </tr>
      </table>
  </td>
</tr>
</table>
</td>
</tr>
</table>
</body>
</html>
"
          $$email_text = $header + $list_of_volumes + $footer


end

define handle_error() do
  #error_msg has the response from the api , use that as the error in the email.
  #$$error_msg = $_error["message"]
  $$error_msg = " failed to delete"
  $_error_behavior = "skip"
end

define send_email_mailgun($to) do
  $mailgun_endpoint = "http://smtp.services.rightscale.com/v3/services.rightscale.com/messages"

     $to = gsub($to,"@","%40")

     $post_body="from=policy-cat%40services.rightscale.com&to=" + $to + "&subject=Volume+Policy+Report&text=" + $$email_text


  $$response = http_post(
     url: $mailgun_endpoint,
     headers: { "content-type": "application/x-www-form-urlencoded"},
     body: $post_body
    )
end
