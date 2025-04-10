import { onMount, createEffect } from "solid-js"
import { useSwarm } from "../SwarmContext"
import SectionHeader from "./SectionHeader"
import LoadingSpinner from "./LoadingSpinner"

export default function Gossip() {
	const ctx = useSwarm()

	let containerRef: HTMLDivElement | undefined

	const scrollToBottom = () => {
		if (containerRef) {
			// Use requestAnimationFrame to ensure DOM has updated
			// Ensures we scroll after the browser paints new content
			requestAnimationFrame(() => {
				containerRef!.scrollTop = containerRef!.scrollHeight
			})
		}
	}

	onMount(() => {
		scrollToBottom()
	})

	createEffect(() => {
		// @ts-expect-error - Intentionally unused variable
		const _ = ctx.gossipMessages()
		scrollToBottom()
	})

	const GossipTooltip = () => {
		return (
			<div class="uppercase">
				Gossip shows the outputs from the agents throughout the game, including their responses to 
				the dataset prompts and to each other.
			</div>
		)
	}

	return (
		<section class="flex flex-grow flex-col gap-2">
			<SectionHeader title="gossip" tooltip={GossipTooltip()} />

			<div ref={containerRef} class="overflow-scroll overflow-x-hidden flex-grow min-h-0 max-h-[300px]" id="gossip-container">
				<ul class="list-none">
					{ctx.gossipMessages().length > 0 ? (
						ctx.gossipMessages().map((msg) => {
							return (
								<li class="mt-4">
									<NodeMessage id={msg.node} message={msg.message} />
								</li>
							)
						})
					) : (
						<span>
							<LoadingSpinner message="Fetching gossip..." />
						</span>
					)}
				</ul>
			</div>
		</section>
	)
}

function NodeMessage(props: { id: string; message: string }) {
	const segments = processMessage(props.message)
	return (
		<p class="uppercase">
			<span class="text-gensyn-green">[{props.id}]</span>
			{segments.map((segment) => (
				<span class={segment.isHighlighted ? "font-bold" : ""}>{segment.text}</span>
			))}
		</p>
	)
}

const processMessage = (message: string): { text: string; isHighlighted: boolean }[] => {
	const reAnswer = new RegExp(/\.\.\.Answer:.+$/)
	const reMajority = new RegExp(/\.\.\.Majority:.+$/)
	const reIdentify = new RegExp(/\.\.\.Identify:.+$/)

	// Replace each pattern with a bold version
	// Split message into segments based on patterns
	const segments = []
	let lastIndex = 0
	
	// Find all matches and their positions
	const matches = [
		...message.matchAll(reAnswer),
		...message.matchAll(reMajority), 
		...message.matchAll(reIdentify)
	].sort((a, b) => (a.index ?? 0) - (b.index ?? 0))

	// Build segments array with type info
	for (const match of matches) {
		if (match.index !== undefined) {
			// Add normal text before match
			if (match.index > lastIndex) {
				segments.push({
					text: message.slice(lastIndex, match.index),
					isHighlighted: false
				})
			}
			// Add highlighted match
			segments.push({
				text: match[0],
				isHighlighted: true
			})
			lastIndex = match.index + match[0].length
		}
	}

	// Add remaining text
	if (lastIndex < message.length) {
		segments.push({
			text: message.slice(lastIndex),
			isHighlighted: false
		})
	}

	return segments
}
