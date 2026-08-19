# Create Flows

In Amazon Connect, creating flows is essential for defining how customer interactions are handled. Flows can be created using the Amazon Connect Flow Designer, which provides a visual interface for building contact flows.

## Default Flows

Amazon Connect comes with several default flows that can be used as templates or starting points for creating custom flows. These include:

* Default agent hold
* Default agent transfer
* Default customer queue
* Default customer whisper
* Default agent whisper
* Set the default whisper flow for chat
* Default customer hold
* Default outbound
* Default queue transfer
* Default prompts from Amazon Lex

You can change the default flows, but the recomendation is maintaining the original flow and edit a original flow copy.

## Sample Flows

Amazon Connect provides sample flows that can be imported into your instance. These sample flows demonstrate various functionalities and can be customized to fit your specific needs. Some of the available sample flows include:

* Sample inbound flow
* Sample flow in Amazon Connect for A/B contact distirbution testing
* Sample customer queue priority flow in Amazon Connect
* Sample disconnect flow in Amazon Connect
* Sample queue customer flow in Amazon Connect
* Sample queued callback flow in Amazon Connect
* Sample interruptible queue flow with callback in Amazon Connect
* Sample Lambda integration flow in Amazon Connect
* Sample recording behavior in Amazon Connect
* Sample Screenpop flow in Amazon Connect
* Sample secure customer data entry input in a call with a contact center agent
* Sample secure customer dara entry input in a call with no contact center agent.

## Flow block definitions in the flow designer in Amazon Connect

There is a lot of options to create a custom flow, the list bellow shows the Blocks and its description:

* **Amazon Q in Connect**
* **Authenticate Customer**
* **Call phone number**
* **Cases**
* **Change routing priority / age**
* **Check call progress**
* **Check contact attributes**
* **Check hours of operations**
* **Check queue status**
* **Check Voice ID**
* **Check staffing**
* **Contact tags**
* **Create persistent contact association**
* **Create task**
* **Customer profiles**
* **Disconnect / hang up**
* **Distribute by percentage**
* **End flow / resume**
* **Get customer input**
* **Get queue metrics**
* **Hold customer or agent**
* **AWS Lambda function**
* **Loop**
* **Loop prompts**
* **Play prompt**
* **Resume contact**
* **Return (from module)**
* **Send message**
* **Set callback number**
* **Set contact attributes**
* **Set customer queue flow**
* **Set disconnect flow**
* **Set event flow**
* **Set hold flow**
* **Set logging behavior**
* **Set recording and analytics behavior**
* **Set routing criteria**
* **Set Voice ID**
* **Set Voice**
* **Set whisper flow**
* **Set working queue**
* **Show view**
* **Start media streaming**
* **Stop media streaming**
* **Store customer input**
* **Trasnfer to agent**
* **Transfer to flow**
* **Transfer to phone number**
* **Transfer to queue**
* **Wait**

## Create a conversational AI bots

Amazon Connect allows you to create conversational AI bots using Amazon Lex. These bots can handle customer interactions, provide information, and perform tasks without the need for human agents.

You can check more information [here](https://docs.aws.amazon.com/connect/latest/adminguide/connect-conversational-ai-bots.html)
